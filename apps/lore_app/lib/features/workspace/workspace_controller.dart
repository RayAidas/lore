import 'dart:async';

import 'package:flutter/foundation.dart';
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
    this.revealGateway,
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
  final LibraryRevealGateway? revealGateway;

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
    onChapterSaved: (path, count) =>
        unawaited(_refreshChapterCharacterCount(path, count)),
  );

  final Map<String, Timer> _structureChangeTimers = {};
  final Set<String> _expandedDirectoryPaths = {};
  StreamSubscription<DocumentChange>? _changeSubscription;
  int _treeRevision = 0;
  String? _lastSavedChapterPath;
  int _statsLabelCacheRevision = -1;
  final Map<String, String?> _statsLabelCache = {};
  LibraryFailure? _workspaceFailure;
  bool _disposed = false;
  Future<void>? _foregroundReconciliation;

  List<WorkspaceTab> get tabs => _tabsStore.tabs;

  List<WorkspaceTab> tabsForGroup(WorkspaceEditorGroupId groupId) =>
      _tabsStore.tabsForGroup(groupId);

  WorkspaceEditorGroupId groupForTab(WorkspaceTab tab) =>
      _tabsStore.groupForTab(tab);

  List<OpenDocument> get documents => _tabsStore.documents;

  String? get activePath => _tabsStore.activePath;

  String? activePathForGroup(WorkspaceEditorGroupId groupId) =>
      _tabsStore.activePathForGroup(groupId);

  OpenDocument? activeDocumentForGroup(WorkspaceEditorGroupId groupId) =>
      _tabsStore.activeDocumentForGroup(groupId);

  WorkspaceEditorGroupId get focusedGroupId => _tabsStore.focusedGroupId;

  bool get isSplit => _tabsStore.isSplit;

  double get splitRatio => _tabsStore.splitRatio;

  String? get selectedPath => _tabsStore.selectedPath;

  LibraryEntry? get selectedEntry => _tabsStore.selectedEntry;

  List<NovelSnapshot> get novels => _novelStore.novels;

  /// 目录树节点尾标：章节字数（未计算返回 null）、卷/小说章节数；其余节点 null。
  /// 结果按 [_treeRevision] 缓存——卷/小说分支要遍历 contentTree，目录树每次
  /// 重建都会调，缓存避免重复 O(N) 扫描。
  String? statsLabelFor(LibraryEntry entry) {
    if (_statsLabelCacheRevision != _treeRevision) {
      _statsLabelCache.clear();
      _statsLabelCacheRevision = _treeRevision;
    }
    return _statsLabelCache.putIfAbsent(
      entry.relativePath,
      () => _computeStatsLabel(entry),
    );
  }

  String? _computeStatsLabel(LibraryEntry entry) {
    final novel = _novelStore.novelByEntryValue(entry.novelId);
    if (novel == null) {
      return null;
    }
    switch (entry.semanticKind) {
      case LibraryEntrySemanticKind.chapter:
        final semanticId = entry.semanticId;
        if (semanticId == null) {
          return null;
        }
        final node = novel.contentTree.nodeById(ContentId(semanticId));
        if (node == null || node.type != ContentNodeType.chapter) {
          return null;
        }
        final count = node.characterCount;
        return count == null ? null : '$count 字';
      case LibraryEntrySemanticKind.volume:
        final semanticId = entry.semanticId;
        if (semanticId == null) {
          return null;
        }
        final chapterCount = novel.contentTree
            .childrenOf(ContentId(semanticId))
            .where((node) => node.type == ContentNodeType.chapter)
            .length;
        return '$chapterCount 章';
      case LibraryEntrySemanticKind.novel:
        final chapterCount = novel.contentTree.nodes
            .where((node) => node.type == ContentNodeType.chapter)
            .length;
        return '$chapterCount 章';
      case LibraryEntrySemanticKind.body:
      case null:
        return null;
    }
  }

  /// 在系统文件管理器中显示条目（macOS Finder）。平台不支持时抛
  /// [LibraryOperationException]（platformUnsupported）。
  Future<void> revealEntry(String relativePath) async {
    final gateway = revealGateway;
    if (gateway == null) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.platformUnsupported,
          message: '当前平台不支持在文件管理器中显示。',
        ),
      );
    }
    await gateway.reveal(session.access, relativePath: relativePath);
  }

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
    // 冷启动回填：旧书库（content.json 无 characterCount）首开时异步补字数。
    _prefillAfterLoad();
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

  /// 按路径查询注册章节节点：供 tab 右键菜单判断「重命名/删除」应走结构服务
  /// （[renameContentNode]/[deleteContentNode]）还是普通文件操作
  /// （[renameSelected]/[deleteSelectedEntry]）。散文件返回 null。
  ({NovelId novelId, ContentId nodeId})? chapterNodeForPath(
    String relativePath,
  ) {
    final match = _novelStore.chapterNodeForPath(relativePath);
    if (match == null) {
      return null;
    }
    return (novelId: match.novel.metadata.id, nodeId: match.node.id);
  }

  void dismissWorkspaceFailure() {
    _workspaceFailure = null;
    _notify();
  }

  Future<List<LibraryEntry>> listChildren({String relativePath = ''}) {
    return service.listChildren(
      session,
      relativePath: relativePath,
      semanticEntries: initialized ? _novelStore.semanticEntryIndex : null,
    );
  }

  bool isDirectoryExpanded(String relativePath) =>
      _expandedDirectoryPaths.contains(relativePath);

  List<String> get expandedDirectoryPaths =>
      List.unmodifiable(_expandedDirectoryPaths);

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

  /// 由已解析的卷/章区段导入整本 TXT 小说（见 [TxtNovelParser]）。重名时抛
  /// `LibraryFailureCode.alreadyExists`，由调用方负责重命名循环。
  Future<NovelStructureMutation> importNovel({
    required String title,
    required List<ParsedSection> sections,
  }) async {
    final mutation = await _requireNovelStructureService().importNovel(
      session,
      title: title,
      sections: sections,
    );
    _applyStructureMutation(mutation);
    return mutation;
  }

  /// 当前书库是否存在同名小说（基于内存 [novels]，与目录树展示一致）。
  bool novelTitleExists(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    return novels.any((novel) => novel.metadata.title == trimmed);
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
    await openPath(mutation.entry!.relativePath);
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

  void focusGroup(WorkspaceEditorGroupId groupId) =>
      _tabsStore.focusGroup(groupId);

  void setSplitRatio(double value) => _tabsStore.setSplitRatio(value);

  void reorderTab(WorkspaceEditorGroupId groupId, int oldIndex, int newIndex) =>
      _tabsStore.reorderTab(groupId, oldIndex, newIndex);

  void moveTab(
    WorkspaceTab tab,
    WorkspaceEditorGroupId destination, {
    int? index,
  }) => _tabsStore.moveTab(tab, destination, index: index);

  void splitRight(WorkspaceTab tab) => _tabsStore.splitRight(tab);

  void closeSplit() => _tabsStore.closeSplit();

  void setPreview(OpenDocument document, bool showPreview) =>
      _tabsStore.setPreview(document, showPreview);

  /// 更新章节副标题（锁定前缀 `第N章` 不可改）；改动会触发脏标记与自动保存。
  void updateChapterTitleSubtitle(OpenDocument document, String subtitle) =>
      _tabsStore.updateChapterTitleSubtitle(document, subtitle);

  /// 副标题改动后防抖触发的「标题→文件名」同步：把待写正文先落盘，再按
  /// `第N章 [副标题]` 重命名注册章节文件；目录树与 Tab 经既有 pathChanges 跟随。
  /// 非注册章节（散文件）或未启用结构服务时静默跳过。
  Future<void> _syncChapterTitle(OpenDocument document) async {
    if (novelStructureService == null || !_isOpen(document)) {
      return;
    }
    try {
      // 先确保正文（含新副标题的首行）落盘，再重命名——避免文件名与内容首行错位。
      if (document.saveFuture != null) {
        await document.saveFuture;
      }
      if (!_isOpen(document)) return;
      if (document.hasUnsavedChanges) {
        await saveDocument(document);
      }
      if (!_isOpen(document)) return;
      final number = document.chapterNumber;
      if (number == null) return;
      final match = _novelStore.chapterNodeForPath(document.relativePath);
      if (match == null) return;
      final desiredStem = ChapterTitleText.titleLine(
        number,
        ChapterTitleText.sanitizeForFilename(document.chapterTitleSubtitle),
      );
      final currentStem = p.basenameWithoutExtension(document.relativePath);
      if (desiredStem == currentStem) return;
      await renameContentNode(
        match.novel.metadata.id,
        match.node.id,
        desiredStem,
      );
    } on LibraryOperationException catch (error) {
      if (!_isOpen(document)) return;
      _setWorkspaceFailure(error.failure);
      _notify();
    } catch (error) {
      // 副标题同步是后台防抖任务：标签可能在 await 期间被关闭（控制器随后
      // dispose）、或某次监听回调抛错。这些都不应作为未处理异步错误崩溃 isolate。
      // 调试时抛出便于排查，发布时静默放弃本次同步。
      if (kDebugMode) rethrow;
    }
  }

  /// 该文档是否仍是当前打开的标签（用于后台任务在 await 后判断是否应继续）。
  bool _isOpen(OpenDocument document) => documents.contains(document);

  Future<bool> saveActive() => _tabsStore.saveActive();

  Future<bool> saveDocument(OpenDocument document) =>
      _tabsStore.saveDocument(document);

  Future<bool> closeTab(WorkspaceTab tab) => _tabsStore.closeTab(tab);

  Future<bool> closeDocument(OpenDocument document) =>
      _tabsStore.closeDocument(document);

  /// 批量关闭：逐个尝试 [closeTab]，冲突态等无法保存的 tab 保留并出现在返回
  /// 列表中（供 UI 提示「N 个标签未关闭」）。
  ///
  /// 以**相对路径**而非 tab 实例作为关闭目标，并在每次关闭前按路径重新查找
  /// 当前实例——Deferred→OpenDocument 的就地激活会替换实例，按路径键控可避免
  /// 漏关。非活动路径先关、活动路径最后关：关闭活动 tab 会触发
  /// `unawaited(activateTab(邻居))`，若邻居是 DeferredDocument 且也在候选中，
  /// 其后 `_loadDeferredDocument` 的异步重插/dispose 会与后续关闭竞态（泄漏幽灵
  /// tab 或重复 dispose）；把活动留到最后，候选中的 Deferred 邻居已被先行关闭，
  /// 激活只会作用于非候选 tab。
  Future<List<WorkspaceTab>> closeOthers(WorkspaceTab keep) {
    final groupId = _tabsStore.groupForTab(keep);
    return _closePaths([
      for (final tab in tabsForGroup(groupId))
        if (tab.relativePath != keep.relativePath) tab.relativePath,
    ], groupId: groupId);
  }

  Future<List<WorkspaceTab>> closeTabsToRight(WorkspaceTab anchor) {
    final groupId = _tabsStore.groupForTab(anchor);
    final anchorPath = anchor.relativePath;
    final groupTabs = tabsForGroup(groupId);
    final index = groupTabs.indexWhere((tab) => tab.relativePath == anchorPath);
    if (index < 0) {
      return Future.value(const <WorkspaceTab>[]);
    }
    return _closePaths([
      for (final tab in groupTabs.sublist(index + 1)) tab.relativePath,
    ], groupId: groupId);
  }

  Future<List<WorkspaceTab>> closeAllTabs() =>
      _closePaths([for (final tab in tabs) tab.relativePath]);

  Future<List<WorkspaceTab>> closeAllTabsInGroup(WorkspaceTab anchor) {
    final groupId = _tabsStore.groupForTab(anchor);
    return _closePaths([
      for (final tab in tabsForGroup(groupId)) tab.relativePath,
    ], groupId: groupId);
  }

  Future<List<WorkspaceTab>> _closePaths(
    List<String> paths, {
    WorkspaceEditorGroupId? groupId,
  }) async {
    final stuck = <WorkspaceTab>[];
    final active = groupId == null ? activePath : activePathForGroup(groupId);
    // 非活动先关、活动最后关——见上方文档注释对 activateTab 竞态的说明。
    final ordered = <String>[
      ...paths.where((path) => path != active),
      ...paths.where((path) => path == active),
    ];
    for (final path in ordered) {
      final tab = tabs
          .where(
            (candidate) =>
                candidate.relativePath == path &&
                (groupId == null ||
                    _tabsStore.groupForTab(candidate) == groupId),
          )
          .firstOrNull;
      if (tab == null) {
        continue; // 已被前面关闭波及（如目录删除连带）。
      }
      if (!await closeTab(tab)) {
        stuck.add(tab);
      }
    }
    return stuck;
  }

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
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.platformUnsupported,
          message: '回收站不可用。',
        ),
      );
    }
    await trash.purge(session.access, trashToken: token);
    // 广播回收站列表变化：清空/永久删除虽不改目录树，但回收站面板与其它
    // 订阅者需感知（补齐此前遗漏的 notify，避免页面不在栈顶时状态不同步）。
    _notify();
  }

  Future<void> emptyTrash() async {
    final trash = trashRepository;
    if (trash == null) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.platformUnsupported,
          message: '回收站不可用。',
        ),
      );
    }
    await trash.empty(session.access);
    _notify();
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

  void _applyStructureMutation(
    NovelStructureMutation mutation, {
    bool semanticStructureChanged = true,
  }) {
    _novelStore.replace(
      mutation.snapshot,
      semanticStructureChanged: semanticStructureChanged,
    );
    for (final change in mutation.pathChanges) {
      _tabsStore.updatePathsAfterRename(change.oldPath, change.newPath);
      _remapExpandedPaths(change.oldPath, change.newPath);
    }
    // 仅在发生路径变更（重命名/移动）时刷新已打开章节的编号——编号只在文件名变更
    // 时才会改变。字数更新（每次保存都会触发）等无 pathChanges 的结构变更跳过，
    // 避免在保存热路径上对全部章节节点做无意义的扫描。
    if (mutation.pathChanges.isNotEmpty) {
      _syncOpenChapterNumbers(mutation);
    }
    final entry = mutation.entry;
    if (entry != null) {
      _tabsStore.selectEntry(entry);
    }
    _treeRevision += 1;
    _tabsStore.scheduleSessionSave();
    _notify();
  }

  /// 结构变更后，按最新快照刷新已打开章节标签的锁定前缀编号（chapterNumber）。
  ///
  /// 存储层 renameNode 已让磁盘首行与新文件名一致；但已打开标签的
  /// [OpenDocument.chapterNumber] 仍停留在旧首行的解析值，且文件 watch 回流
  /// 在路径被 [WorkspaceTabsStore.updatePathsAfterRename] 重映射后未必命中，
  /// 故在此显式同步。正文不含标题行，编号一改标题栏即变；副标题与正文均不动。
  void _syncOpenChapterNumbers(NovelStructureMutation mutation) {
    for (final node in mutation.snapshot.contentTree.nodes) {
      if (node.type != ContentNodeType.chapter || node.number == null) {
        continue;
      }
      final path = p.join(mutation.snapshot.rootPath, node.relativePath);
      _tabsStore.updateChapterNumberForPath(path, node.number!);
    }
  }

  /// 把字数写回 content.json 并刷新内存快照。字数更新是 best-effort 缓存，
  /// 失败静默（下次保存/reconcile 修正）。counts 抛出的
  /// [LibraryOperationException]（如读盘失败）同样被吞掉。
  Future<void> _applyChapterCounts(
    NovelId novelId,
    Future<Map<ContentId, int>> counts,
  ) async {
    try {
      final map = await counts;
      if (map.isEmpty) {
        return;
      }
      final mutation = await _requireNovelStructureService()
          .updateChapterCharacterCounts(
            session,
            novelId: novelId,
            characterCounts: map,
          );
      _applyStructureMutation(mutation, semanticStructureChanged: false);
    } on LibraryOperationException {
      // 字数更新失败：静默，下次保存/reconcile 修正。
    }
  }

  /// 章节保存后把最新字数写回 content.json（仅注册章节；散文件/卷目录跳过）。
  Future<void> _refreshChapterCharacterCount(
    String relativePath,
    int characterCount,
  ) async {
    // 标记自身保存：文件监听会把这次 .md 写入也当 modified 回流，跳过它
    // 避免与本次回写重复写 content.json（onChapterSaved 同步先于 watch microtask）。
    _lastSavedChapterPath = relativePath;
    final hit = _novelStore.chapterNodeForPath(relativePath);
    if (hit == null) {
      return;
    }
    await _applyChapterCounts(
      hit.novel.metadata.id,
      Future.value({hit.node.id: characterCount}),
    );
  }

  /// 外部编辑器修改章节后重算字数写回（覆盖持久化值，保证正确性）。
  Future<void> _refreshChapterCharacterCountFromDisk(
    String relativePath,
  ) async {
    final hit = _novelStore.chapterNodeForPath(relativePath);
    if (hit == null) {
      return;
    }
    final format = hit.novel.metadata.chapterFormat == ChapterFormat.text
        ? DocumentFormat.text
        : DocumentFormat.markdown;
    await _applyChapterCounts(
      hit.novel.metadata.id,
      _readDiskChapterCount(relativePath, format, hit.node.id),
    );
  }

  Future<Map<ContentId, int>> _readDiskChapterCount(
    String relativePath,
    DocumentFormat format,
    ContentId nodeId,
  ) async {
    final doc = await service.readDocument(
      session,
      DocumentRef(relativePath: relativePath, format: format),
    );
    return {nodeId: characterCountOf(doc.text)};
  }

  /// 旧书库回填：novel 中 characterCount==null 的章节批量读文件算字数并写回。
  /// 无 null 章节时跳过（正常启动零成本）；旧书库首开一次性。
  Future<void> _prefillCharacterCounts(NovelId novelId) async {
    final overviewService = novelOverviewService;
    final novel = _novelStore.novelById(novelId);
    if (overviewService == null || novel == null) {
      return;
    }
    final hasNull = novel.contentTree.nodes.any(
      (node) =>
          node.type == ContentNodeType.chapter && node.characterCount == null,
    );
    if (!hasNull) {
      return;
    }
    await _applyChapterCounts(
      novelId,
      overviewService.chapterCharacterCounts(session, novelId: novelId),
    );
  }

  /// 加载小说结构后，对所有 novel 触发字数回填（旧书库 characterCount==null
  /// 的章节异步读文件回填）。供 initialize 与 _loadNovelStructures 复用。
  void _prefillAfterLoad() {
    for (final novel in _novelStore.novels) {
      unawaited(_prefillCharacterCounts(novel.metadata.id));
    }
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
    } else if (!treeChanged) {
      if (change.relativePath == _lastSavedChapterPath) {
        // 自身保存触发的 modified 回流：字数已由 onChapterSaved 写回，跳过。
        _lastSavedChapterPath = null;
      } else {
        // 章节内容外部修改：重算字数写回（覆盖持久化值）。
        unawaited(_refreshChapterCharacterCountFromDisk(change.relativePath));
      }
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
      return;
    }
    // 旧书库回填：characterCount==null 的章节异步读文件算字数写回 content.json。
    _prefillAfterLoad();
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
