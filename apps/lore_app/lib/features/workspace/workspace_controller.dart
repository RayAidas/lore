import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:path/path.dart' as p;

import 'workspace_document.dart';
import 'workspace_novel_store.dart';
import 'workspace_tabs_store.dart';

export 'workspace_document.dart';

/// 工作区控制器：跨 [WorkspaceTabsStore]（标签/文档/导航）与
/// [WorkspaceNovelStore]（小说结构）编排，持有目录树版本号、工作区级失败态、
/// 文件监听与回收站/概览入口。
final class WorkspaceController extends ChangeNotifier {
  WorkspaceController({
    required this.session,
    required this.service,
    this.novelStructureService,
    this.novelOverviewService,
    this.writingProgressRepository,
    this.trashRepository,
  }) : _novelStore = WorkspaceNovelStore(
         service: novelStructureService,
         session: session,
       );

  final LibrarySession session;
  final LibraryWorkspaceService service;
  final NovelStructureService? novelStructureService;
  final NovelOverviewService? novelOverviewService;
  final WritingProgressRepository? writingProgressRepository;
  final TrashRepository? trashRepository;

  final WorkspaceNovelStore _novelStore;
  late final WorkspaceTabsStore _tabsStore = WorkspaceTabsStore(
    service: service,
    session: session,
    writingProgressRepository: writingProgressRepository,
    notify: _notify,
    novelIdForPath: _novelStore.novelIdForPath,
    bumpTreeRevision: _bumpTreeRevision,
    confirmStructuralChange: _recordStructuralChange,
    expandedDirectoryPaths: () => _expandedDirectoryPaths.toList(),
    reportFailure: _setWorkspaceFailure,
    requestTitleSync: _syncChapterTitle,
  );

  final Map<String, Timer> _structureChangeTimers = {};
  final Set<String> _expandedDirectoryPaths = {};
  StreamSubscription<DocumentChange>? _changeSubscription;
  int _treeRevision = 0;
  LibraryFailure? _workspaceFailure;
  bool _disposed = false;
  Future<void>? _foregroundReconciliation;

  List<WorkspaceTab> get tabs => _tabsStore.tabs;

  List<OpenDocument> get documents => _tabsStore.documents;

  String? get activePath => _tabsStore.activePath;

  String? get selectedPath => _tabsStore.selectedPath;

  LibraryEntry? get selectedEntry => _tabsStore.selectedEntry;

  List<NovelSnapshot> get novels => _novelStore.novels;

  List<ReconciliationIssue> get reconciliationIssues => _novelStore.issues;

  NovelSnapshot? get selectedNovel =>
      _novelStore.novelByEntryValue(_tabsStore.selectedEntry?.novelId);

  ContentNode? get selectedContentNode {
    final entry = _tabsStore.selectedEntry;
    final novel = selectedNovel;
    if (entry?.semanticId == null || novel == null) {
      return null;
    }
    return novel.contentTree.nodeById(ContentId(entry!.semanticId!));
  }

  int get treeRevision => _treeRevision;

  LibraryFailure? get workspaceFailure => _workspaceFailure;

  bool get initialized => _tabsStore.initialized;

  OpenDocument? get activeDocument => _tabsStore.activeDocument;

  Future<void> initialize() async {
    if (_tabsStore.initialized) {
      return;
    }
    WorkspaceSessionSnapshot? saved;
    try {
      saved = await service.loadSession(session);
    } catch (_) {
      _workspaceFailure = const LibraryFailure(
        code: LibraryFailureCode.io,
        message: '无法恢复上次打开的标签。',
      );
    }
    _expandedDirectoryPaths
      ..clear()
      ..addAll(saved?.expandedDirectoryPaths ?? const []);
    _tabsStore.restoreTabs(saved);
    _changeSubscription = service
        .watchDocuments(session)
        .listen(_handleDocumentChange, onError: (_) {});
    // 清理 90 天前的写作进度记录，避免 SharedPreferences 无限增长。
    final progress = writingProgressRepository;
    if (progress != null) {
      unawaited(
        progress.pruneBefore(
          DateTime.now().toUtc().subtract(const Duration(days: 90)),
        ),
      );
    }
    final loadFailure = await _novelStore.load();
    if (loadFailure != null) {
      _workspaceFailure = loadFailure;
    }
    _tabsStore.markInitialized();
    _notify();
    unawaited(_reconcileLoadedNovels());
    await _tabsStore.activateInitialTab();
  }

  /// Rescans state after returning from the background.
  ///
  /// SAF providers do not expose a reliable recursive watch stream, so this
  /// also provides the consistency path for external Android file changes.
  Future<void> reconcileAfterForeground() {
    return _foregroundReconciliation ??= _performForegroundReconciliation()
        .whenComplete(() => _foregroundReconciliation = null);
  }

  Future<void> _performForegroundReconciliation() async {
    if (!_tabsStore.initialized || _disposed) {
      return;
    }
    await _loadNovelStructures();
    await _reconcileLoadedNovels();
    await _tabsStore.reconcileOpenDocuments();
    _treeRevision += 1;
    _notify();
  }

  void selectPath(String relativePath) {
    _tabsStore.selectPath(relativePath);
    _notify();
  }

  void selectEntry(LibraryEntry entry) {
    _tabsStore.selectEntry(entry);
    _notify();
  }

  void dismissWorkspaceFailure() {
    _workspaceFailure = null;
    _notify();
  }

  Future<List<LibraryEntry>> listChildren({String relativePath = ''}) {
    return service.listChildren(session, relativePath: relativePath);
  }

  bool isDirectoryExpanded(String relativePath) =>
      _expandedDirectoryPaths.contains(relativePath);

  void setDirectoryExpanded(String relativePath, bool expanded) {
    final changed = expanded
        ? _expandedDirectoryPaths.add(relativePath)
        : _expandedDirectoryPaths.remove(relativePath);
    if (changed) {
      _tabsStore.scheduleSessionSave();
    }
  }

  Future<NovelStructureMutation> createNovel(
    String title, {
    ChapterFormat? chapterFormat,
  }) async {
    final mutation = await _requireNovelStructureService().createNovel(
      session,
      title: title,
      chapterFormat: chapterFormat ?? ChapterFormat.markdown,
    );
    _applyStructureMutation(mutation);
    return mutation;
  }

  Future<NovelStructureMutation> registerExistingNovel(String path) async {
    final mutation = await _requireNovelStructureService()
        .registerExistingNovel(session, relativePath: path);
    _applyStructureMutation(mutation);
    return mutation;
  }

  Future<NovelStructureMutation> createVolume(NovelId novelId) async {
    final mutation = await _requireNovelStructureService().createVolume(
      session,
      novelId: novelId,
    );
    _applyStructureMutation(mutation);
    return mutation;
  }

  Future<NovelStructureMutation> renameNovel(
    NovelId novelId,
    String newName,
  ) async {
    final mutation = await _requireNovelStructureService().renameNovel(
      session,
      novelId: novelId,
      newName: newName,
    );
    _applyStructureMutation(mutation);
    return mutation;
  }

  Future<NovelStructureMutation> renameBody(
    NovelId novelId,
    String newName,
  ) async {
    final mutation = await _requireNovelStructureService().renameBody(
      session,
      novelId: novelId,
      newName: newName,
    );
    _applyStructureMutation(mutation);
    return mutation;
  }

  Future<NovelStructureMutation> createChapter(
    NovelId novelId, {
    ContentId? volumeId,
  }) async {
    final mutation = await _requireNovelStructureService().createChapter(
      session,
      novelId: novelId,
      volumeId: volumeId,
    );
    _applyStructureMutation(mutation);
    await openPath(mutation.entry.relativePath);
    return mutation;
  }

  Future<NovelStructureMutation> renameContentNode(
    NovelId novelId,
    ContentId nodeId,
    String newName,
  ) async {
    final mutation = await _requireNovelStructureService().renameNode(
      session,
      novelId: novelId,
      nodeId: nodeId,
      newName: newName,
    );
    _applyStructureMutation(mutation);
    return mutation;
  }

  Future<NovelStructureMutation> moveChapter(
    NovelId novelId,
    ContentId chapterId, {
    ContentId? volumeId,
  }) async {
    final mutation = await _requireNovelStructureService().moveChapter(
      session,
      novelId: novelId,
      chapterId: chapterId,
      volumeId: volumeId,
    );
    _applyStructureMutation(mutation);
    return mutation;
  }

  Future<NovelStructureMutation> reorderContentNode(
    NovelId novelId,
    ContentId nodeId,
    int newIndex,
  ) async {
    final mutation = await _requireNovelStructureService().reorderNode(
      session,
      novelId: novelId,
      nodeId: nodeId,
      newIndex: newIndex,
    );
    _applyStructureMutation(mutation);
    return mutation;
  }

  Future<void> openPath(String relativePath) =>
      _tabsStore.openPath(relativePath);

  Future<LibraryEntry> createDirectory({
    required String parentPath,
    required String name,
  }) async {
    final entry = await service.createDirectory(
      session,
      parentPath: parentPath,
      name: name,
    );
    _tabsStore.selectEntry(entry);
    _treeRevision += 1;
    _notify();
    return entry;
  }

  Future<LibraryEntry> createDocument({
    required String parentPath,
    required String name,
    required DocumentFormat format,
  }) async {
    final entry = await service.createDocument(
      session,
      parentPath: parentPath,
      name: name,
      format: format,
    );
    _tabsStore.selectEntry(entry);
    _treeRevision += 1;
    await openPath(entry.relativePath);
    return entry;
  }

  Future<LibraryEntry> renameSelected(String newName) async {
    final sourcePath = _tabsStore.selectedPath;
    if (sourcePath == null || sourcePath.isEmpty) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.notFound,
          message: '请先选择要重命名的文件或文件夹。',
        ),
      );
    }
    final entry = await service.renameEntry(
      session,
      relativePath: sourcePath,
      newName: newName,
    );
    _tabsStore.updatePathsAfterRename(sourcePath, entry.relativePath);
    _remapExpandedPaths(sourcePath, entry.relativePath);
    _tabsStore.selectEntry(entry);
    _treeRevision += 1;
    _tabsStore.scheduleSessionSave();
    _notify();
    return entry;
  }

  Future<void> activateTab(WorkspaceTab tab) => _tabsStore.activateTab(tab);

  void setPreview(OpenDocument document, bool showPreview) =>
      _tabsStore.setPreview(document, showPreview);

  /// 更新章节副标题（锁定前缀 `第N章` 不可改）；改动会触发脏标记与自动保存。
  void updateChapterTitleSubtitle(OpenDocument document, String subtitle) =>
      _tabsStore.updateChapterTitleSubtitle(document, subtitle);

  /// 副标题改动后防抖触发的「标题→文件名」同步：把待写正文先落盘，再按
  /// `第N章 [副标题]` 重命名注册章节文件；目录树与 Tab 经既有 pathChanges 跟随。
  /// 非注册章节（散文件）或未启用结构服务时静默跳过。
  Future<void> _syncChapterTitle(OpenDocument document) async {
    if (novelStructureService == null) {
      return;
    }
    // 先确保正文（含新副标题的首行）落盘，再重命名——避免文件名与内容首行错位。
    if (document.saveFuture != null) {
      await document.saveFuture;
    }
    if (document.hasUnsavedChanges) {
      await saveDocument(document);
    }
    final number = document.chapterNumber;
    if (number == null) {
      return;
    }
    final match = _novelStore.chapterNodeForPath(document.relativePath);
    if (match == null) {
      return;
    }
    final desiredStem = ChapterTitleText.titleLine(
      number,
      ChapterTitleText.sanitizeForFilename(document.chapterTitleSubtitle),
    );
    final currentStem = p.basenameWithoutExtension(document.relativePath);
    if (desiredStem == currentStem) {
      return;
    }
    try {
      await renameContentNode(
        match.novel.metadata.id,
        match.node.id,
        desiredStem,
      );
    } on LibraryOperationException catch (error) {
      _setWorkspaceFailure(error.failure);
      _notify();
    }
  }

  Future<bool> saveActive() => _tabsStore.saveActive();

  Future<bool> saveDocument(OpenDocument document) =>
      _tabsStore.saveDocument(document);

  Future<bool> closeTab(WorkspaceTab tab) => _tabsStore.closeTab(tab);

  Future<bool> closeDocument(OpenDocument document) =>
      _tabsStore.closeDocument(document);

  Future<bool> flushAll() => _tabsStore.flushAll();

  Future<void> reloadConflict(OpenDocument document) =>
      _tabsStore.reloadConflict(document);

  Future<void> saveConflictCopy(OpenDocument document) =>
      _tabsStore.saveConflictCopy(document);

  Future<DeletionResult> deleteContentNode(
    NovelId novelId,
    ContentId nodeId,
  ) async {
    final result = await _requireNovelStructureService().deleteNode(
      session,
      novelId: novelId,
      nodeId: nodeId,
    );
    _applyDeletionResult(result);
    return result;
  }

  Future<DeletionResult> deleteNovel(NovelId novelId) async {
    final result = await _requireNovelStructureService().deleteNovel(
      session,
      novelId: novelId,
    );
    _novelStore.remove(novelId);
    _applyDeletionResult(result);
    _notify();
    return result;
  }

  Future<DeletionResult> deleteSelectedEntry() async {
    final sourcePath = _tabsStore.selectedPath;
    if (sourcePath == null || sourcePath.isEmpty) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.notFound,
          message: '请先选择要删除的文件或文件夹。',
        ),
      );
    }
    final result = await service.deleteEntry(session, relativePath: sourcePath);
    _applyDeletionResult(result);
    return result;
  }

  Future<List<TrashItem>> listTrashItems() async {
    final trash = trashRepository;
    if (trash == null) {
      return const [];
    }
    return trash.listItems(session.access);
  }

  Future<TrashItem> restoreTrashItem(
    String token, {
    RestoreConflictStrategy strategy = RestoreConflictStrategy.rename,
  }) async {
    final trash = trashRepository;
    if (trash == null) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.platformUnsupported,
          message: '回收站不可用。',
        ),
      );
    }
    final item = await trash.restore(
      session.access,
      trashToken: token,
      strategy: strategy,
    );
    // storage 已在恢复后重扫内容树并写盘；这里只刷新内存快照与树版本，
    // 不再重复 reconcile（避免与 storage 的 _reconcileAfterRestore 重复 scan）。
    final structureService = novelStructureService;
    if (item.novelId != null && structureService != null) {
      try {
        final fresh = await structureService.loadNovel(
          session,
          novelId: NovelId(item.novelId!),
        );
        _novelStore.replace(fresh);
      } on LibraryOperationException {
        // 小说可能已不在注册表，忽略；由 _loadNovelStructures 收敛。
      }
    }
    _treeRevision += 1;
    unawaited(_loadNovelStructures());
    _notify();
    return item;
  }

  Future<void> purgeTrashItem(String token) async {
    final trash = trashRepository;
    if (trash == null) {
      return;
    }
    await trash.purge(session.access, trashToken: token);
  }

  Future<void> emptyTrash() async {
    final trash = trashRepository;
    if (trash == null) {
      return;
    }
    await trash.empty(session.access);
  }

  Future<NovelOverview> loadNovelOverview(
    NovelId novelId, {
    int dailyWordGoal = 0,
  }) async {
    final overviewService = novelOverviewService;
    if (overviewService == null) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.platformUnsupported,
          message: '当前工作区未启用小说概览。',
        ),
      );
    }
    return overviewService.computeOverview(
      session,
      novelId: novelId,
      dailyWordGoal: dailyWordGoal,
    );
  }

  void _applyStructureMutation(NovelStructureMutation mutation) {
    _novelStore.replace(mutation.snapshot);
    for (final change in mutation.pathChanges) {
      _tabsStore.updatePathsAfterRename(change.oldPath, change.newPath);
      _remapExpandedPaths(change.oldPath, change.newPath);
    }
    _tabsStore.selectEntry(mutation.entry);
    _treeRevision += 1;
    _tabsStore.scheduleSessionSave();
    _notify();
  }

  void _applyDeletionResult(DeletionResult result) {
    if (result.snapshot != null) {
      _novelStore.replace(result.snapshot!);
    }
    _tabsStore.applyDeletionPathChanges(result.pathChanges);
    for (final change in result.pathChanges) {
      _removeExpandedPaths(change.oldPath);
    }
    _treeRevision += 1;
    _tabsStore.scheduleSessionSave();
    _notify();
  }

  void _remapExpandedPaths(String oldPath, String newPath) {
    final affected = _expandedDirectoryPaths
        .where((path) => path == oldPath || p.isWithin(oldPath, path))
        .toList();
    for (final path in affected) {
      _expandedDirectoryPaths.remove(path);
      final suffix = path == oldPath ? '' : p.relative(path, from: oldPath);
      _expandedDirectoryPaths.add(
        suffix.isEmpty ? newPath : p.join(newPath, suffix),
      );
    }
  }

  void _removeExpandedPaths(String removedPath) {
    _expandedDirectoryPaths.removeWhere(
      (path) => path == removedPath || p.isWithin(removedPath, path),
    );
  }

  void _handleDocumentChange(DocumentChange change) {
    final treeChanged = change.type != DocumentChangeType.modified;
    final changedDocument = _tabsStore.documents
        .where((document) => document.relativePath == change.relativePath)
        .firstOrNull;
    final deferStructuralChange =
        treeChanged &&
        changedDocument != null &&
        !changedDocument.sourceMissing &&
        changedDocument.failure?.code != LibraryFailureCode.notFound;
    if (treeChanged && !deferStructuralChange) {
      _recordStructuralChange(change.relativePath);
    }
    _tabsStore.handleDocumentChange(
      change,
      confirmMissingAsStructural: deferStructuralChange,
    );
    if (treeChanged && !deferStructuralChange) {
      _notify();
    }
  }

  void _recordStructuralChange(String relativePath) {
    _treeRevision += 1;
    for (final novel in _novelStore.novels) {
      if (relativePath == novel.rootPath ||
          p.isWithin(novel.rootPath, relativePath)) {
        _scheduleStructureReconciliation(novel.metadata.id);
      }
    }
  }

  Future<void> _loadNovelStructures() async {
    final failure = await _novelStore.load();
    if (failure != null) {
      _workspaceFailure = failure;
    }
  }

  Future<void> _reconcileLoadedNovels() async {
    for (final novel in List<NovelSnapshot>.of(_novelStore.novels)) {
      if (_disposed) {
        return;
      }
      await _reconcileNovel(novel.metadata.id);
    }
  }

  NovelStructureService _requireNovelStructureService() {
    final structureService = novelStructureService;
    if (structureService == null) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.platformUnsupported,
          message: '当前工作区未启用小说结构管理。',
        ),
      );
    }
    return structureService;
  }

  void _scheduleStructureReconciliation(NovelId novelId) {
    final key = novelId.value;
    _structureChangeTimers[key]?.cancel();
    _structureChangeTimers[key] = Timer(const Duration(milliseconds: 180), () {
      unawaited(_reconcileNovel(novelId));
    });
  }

  Future<void> _reconcileNovel(NovelId novelId) async {
    if (novelStructureService == null || _disposed) {
      return;
    }
    final failure = await _novelStore.reconcile(novelId);
    if (failure == null) {
      _treeRevision += 1;
    } else {
      _workspaceFailure = failure;
    }
    _notify();
  }

  void _bumpTreeRevision() => _treeRevision += 1;

  void _setWorkspaceFailure(LibraryFailure failure) =>
      _workspaceFailure = failure;

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final timer in _structureChangeTimers.values) {
      timer.cancel();
    }
    unawaited(_changeSubscription?.cancel());
    _tabsStore.dispose();
    super.dispose();
  }
}
