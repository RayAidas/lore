// 回调字段（_notify 等）私有、构造参数公开命名，二者刻意不同名，
// 故不适用 prefer_initializing_formals。
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_editor/lore_editor.dart';
import 'package:path/path.dart' as p;

import 'workspace_document.dart';

/// 工作区标签与文档编辑状态的存储：持有标签、当前激活/选择路径，以及文档
/// 打开/保存/自动保存/冲突/统计/session 持久化/路径重映射等全部机制。
///
/// 不持有 `_treeRevision` / `_workspaceFailure`（归 [WorkspaceController]），
/// 通过构造时注入的回调与其协作：
/// - [notify]：触发控制器整体 notifyListeners；
/// - [bumpTreeRevision]：通知控制器目录树版本号自增；
/// - [reportFailure]：上报需要展示的 [LibraryFailure]；
/// - [novelIdForPath]：按路径查询所属小说（用于写作进度统计）。
///
/// 选择/重命名/删除等会被控制器在自增 treeRevision 后再 notify 的操作，
/// 本类中**不主动 notify**（selectPath/selectEntry/updatePathsAfterRename/
/// applyDeletionPathChanges）；其余操作在原 notify 处通过 [notify] 回调触发。
final class WorkspaceTabsStore {
  WorkspaceTabsStore({
    required this.service,
    required this.session,
    this.writingProgressRepository,
    required void Function() notify,
    required NovelId? Function(String relativePath) novelIdForPath,
    required void Function() bumpTreeRevision,
    required void Function(String relativePath) confirmStructuralChange,
    required List<String> Function() expandedDirectoryPaths,
    required void Function(LibraryFailure failure) reportFailure,
    required Future<void> Function(OpenDocument document) requestTitleSync,
  }) : _notify = notify,
       _novelIdForPath = novelIdForPath,
       _bumpTreeRevision = bumpTreeRevision,
       _confirmStructuralChange = confirmStructuralChange,
       _expandedDirectoryPaths = expandedDirectoryPaths,
       _reportFailure = reportFailure,
       _requestTitleSync = requestTitleSync;

  static const _autoSaveDelay = Duration(milliseconds: 800);
  static const _sessionSaveDelay = Duration(milliseconds: 500);
  static const _statisticsDelay = Duration(milliseconds: 250);
  static const _externalChangeDelay = Duration(milliseconds: 180);
  static const _titleSyncDelay = Duration(milliseconds: 1000);
  static const _maximumRestoredTabs = 20;

  final LibraryWorkspaceService service;
  final LibrarySession session;
  final WritingProgressRepository? writingProgressRepository;
  final void Function() _notify;
  final NovelId? Function(String) _novelIdForPath;
  final void Function() _bumpTreeRevision;
  final void Function(String) _confirmStructuralChange;
  final List<String> Function() _expandedDirectoryPaths;
  final void Function(LibraryFailure) _reportFailure;
  final Future<void> Function(OpenDocument) _requestTitleSync;

  final List<WorkspaceTab> _tabs = [];
  final Map<String, Timer> _externalChangeTimers = {};
  Timer? _sessionSaveTimer;
  String? _activePath;
  String? _selectedPath;
  LibraryEntry? _selectedEntry;
  bool _initialized = false;
  bool _disposed = false;

  List<WorkspaceTab> get tabs => List.unmodifiable(_tabs);

  List<OpenDocument> get documents => _tabs.whereType<OpenDocument>().toList();

  String? get activePath => _activePath;

  String? get selectedPath => _selectedPath;

  LibraryEntry? get selectedEntry => _selectedEntry;

  bool get initialized => _initialized;

  OpenDocument? get activeDocument => _documentForPath(_activePath);

  /// 从会话快照恢复标签（不读取磁盘内容，仅建立 [DeferredDocument] 占位）。
  void restoreTabs(WorkspaceSessionSnapshot? saved) {
    if (saved != null) {
      for (final document in saved.documents.take(_maximumRestoredTabs)) {
        final format = _formatForPath(document.relativePath);
        if (format == null) {
          continue;
        }
        _tabs.add(DeferredDocument(state: document, format: format));
      }
      if (_tabForPath(saved.activePath) != null) {
        _activePath = saved.activePath;
      }
    }
    _activePath ??= _tabs.firstOrNull?.relativePath;
    _selectedPath = _activePath;
  }

  void markInitialized() => _initialized = true;

  /// 供控制器在外部变更（重命名/结构变更）后安排一次防抖的 session 持久化。
  void scheduleSessionSave() => _scheduleSessionSave();

  /// 选择路径（仅逻辑，不 notify——由调用方决定何时 notify）。
  void selectPath(String relativePath) {
    _selectedPath = relativePath;
    _selectedEntry = null;
  }

  /// 选择条目（仅逻辑，不 notify）。
  void selectEntry(LibraryEntry entry) {
    _selectedPath = entry.relativePath;
    _selectedEntry = entry;
  }

  Future<void> openPath(String relativePath) async {
    final format = _formatForPath(relativePath);
    if (format == null) {
      selectPath(relativePath);
      _notify();
      return;
    }
    final existing = _tabForPath(relativePath);
    if (existing != null) {
      await activateTab(existing);
      return;
    }
    await _openDocument(
      DocumentRef(relativePath: relativePath, format: format),
    );
  }

  Future<void> activateTab(WorkspaceTab tab) async {
    WorkspaceTab activated = tab;
    if (tab is DeferredDocument) {
      final loaded = await _loadDeferredDocument(tab);
      if (loaded == null) {
        return;
      }
      activated = loaded;
    }
    _activePath = activated.relativePath;
    _selectedPath = activated.relativePath;
    _selectedEntry = null;
    _scheduleSessionSave();
    _notify();
  }

  /// 初始化末尾激活首个标签（若存在）。
  Future<void> activateInitialTab() async {
    final activeTab = _tabForPath(_activePath);
    if (activeTab != null) {
      await activateTab(activeTab);
    }
  }

  void setPreview(OpenDocument document, bool showPreview) {
    if (!document.isMarkdown || document.showPreview == showPreview) {
      return;
    }
    document.showPreview = showPreview;
    document.notifyChanged();
  }

  /// 更新章节副标题（锁定前缀 `第N章` 不在此方法职责内）。副标题改动独立于
  /// 正文控制器，故显式置脏 + 安排自动保存，使仅改标题也能落盘。同时安排一次
  /// 防抖的标题→文件名同步（由控制器查节点并重命名）。
  void updateChapterTitleSubtitle(OpenDocument document, String subtitle) {
    if (document.chapterNumber == null ||
        subtitle == document.chapterTitleSubtitle) {
      return;
    }
    document.chapterTitleSubtitle = subtitle;
    document.titleDirty = true;
    if (document.saveStatus != DocumentSaveStatus.conflict) {
      document.failure = null;
      document.saveStatus = DocumentSaveStatus.dirty;
      _scheduleAutoSave(document);
      _scheduleTitleSync(document);
    }
    _scheduleSessionSave();
    document.notifyChanged();
  }

  /// 防抖安排一次标题→文件名同步（比自动保存略晚，确保内容先落盘再重命名）。
  void _scheduleTitleSync(OpenDocument document) {
    document.titleSyncTimer?.cancel();
    document.titleSyncTimer = Timer(_titleSyncDelay, () {
      if (_disposed) {
        return;
      }
      unawaited(_requestTitleSync(document));
    });
  }

  /// 把磁盘完整文本重新拆分为「标题栏状态 + 正文」并写回控制器（用于加载、
  /// 冲突重载、外部变更刷新）。selection 为正文相对偏移，超出范围时由控制器夹紧。
  void _applyDiskText(
    OpenDocument document,
    String fullText, {
    TextSelection? selection,
  }) {
    final parsed = ChapterTitleText.tryParse(fullText);
    if (parsed == null) {
      document.chapterNumber = null;
      document.chapterTitleSubtitle = '';
      document.editorController.replaceFromDisk(fullText, selection: selection);
      return;
    }
    document.chapterNumber = parsed.number;
    document.chapterTitleSubtitle = parsed.subtitle;
    document.titleDirty = false;
    document.editorController.replaceFromDisk(
      ChapterTitleText.bodyOf(fullText),
      selection: selection,
    );
  }

  Future<bool> saveActive() async {
    final document = activeDocument;
    return document == null || await saveDocument(document);
  }

  Future<bool> saveDocument(OpenDocument document) {
    final running = document.saveFuture;
    if (running != null) {
      return running;
    }
    final future = _performSave(document);
    document.saveFuture = future;
    return future.whenComplete(() {
      document.saveFuture = null;
    });
  }

  Future<bool> _performSave(OpenDocument document) async {
    document.saveTimer?.cancel();
    if (document.saveStatus == DocumentSaveStatus.conflict) {
      return false;
    }
    while (document.hasUnsavedChanges) {
      final editorSnapshot = document.editorController.buildSnapshot();
      // 捕获本次保存所依据的副标题快照。保存 await 期间用户可能再次改副标题：
      // 仅当磁盘写入成功且副标题在期间未变化时才清脏，否则保留 titleDirty 让
      // 循环再来一轮，避免「保存期间改的副标题」被静默丢弃（关 Tab 时丢失）。
      final subtitleSnapshot = document.chapterTitleSubtitle;
      // 章节标题文档：把「锁定前缀 + 副标题」重组回首行，再拼接正文。副标题经
      // sanitizeForFilename 净化，使落盘首行与文件名（标题同步用同一净化）一致，
      // 避免前导点 / 控制字符造成首行与文件名长期错位、每次编辑都重命名。
      final fullText = document.chapterNumber == null
          ? editorSnapshot.text
          : ChapterTitleText.compose(
              document.chapterNumber!,
              ChapterTitleText.sanitizeForFilename(subtitleSnapshot),
              editorSnapshot.text,
              markdown: document.isMarkdown,
            );
      document.saveStatus = DocumentSaveStatus.saving;
      document.failure = null;
      document.notifyChanged();
      try {
        final result = await service.saveDocument(
          session,
          original: document.snapshot,
          text: fullText,
        );
        switch (result) {
          case DocumentSaveSuccess(:final snapshot):
            document.snapshot = snapshot;
            document.sourceMissing = false;
            document.editorController.markSaved(editorSnapshot.version);
            // 若保存期间副标题又变了，保持脏标记让循环再来一轮写入新值。
            document.titleDirty =
                document.chapterTitleSubtitle != subtitleSnapshot;
            document.saveStatus = document.hasUnsavedChanges
                ? DocumentSaveStatus.dirty
                : DocumentSaveStatus.clean;
          case DocumentSaveConflict(:final diskSnapshot):
            document.conflictSnapshot = diskSnapshot;
            document.sourceMissing = false;
            document.saveStatus = DocumentSaveStatus.conflict;
            document.notifyChanged();
            return false;
        }
      } on LibraryOperationException catch (error) {
        _applyDocumentFailure(document, error.failure);
        document.notifyChanged();
        return false;
      }
      document.notifyChanged();
    }
    _scheduleSessionSave();
    return true;
  }

  Future<bool> closeTab(WorkspaceTab tab) async {
    if (tab is DeferredDocument) {
      return _removeTab(tab);
    }
    return closeDocument(tab as OpenDocument);
  }

  Future<bool> closeDocument(OpenDocument document) async {
    if (document.hasUnsavedChanges && !await saveDocument(document)) {
      return false;
    }
    return _removeTab(document);
  }

  bool _removeTab(WorkspaceTab tab) {
    final index = _tabs.indexOf(tab);
    if (index < 0) {
      return true;
    }
    _tabs.removeAt(index);
    if (_activePath == tab.relativePath) {
      _activePath = _tabs.isEmpty
          ? null
          : _tabs[index.clamp(0, _tabs.length - 1)].relativePath;
      _selectedPath = _activePath;
    }
    tab.dispose();
    _scheduleSessionSave();
    _notify();
    final nextTab = _tabForPath(_activePath);
    if (nextTab is DeferredDocument) {
      unawaited(activateTab(nextTab));
    }
    return true;
  }

  Future<bool> flushAll() async {
    for (final document in List<OpenDocument>.from(documents)) {
      if (document.hasUnsavedChanges && !await saveDocument(document)) {
        return false;
      }
    }
    await persistSession();
    return true;
  }

  Future<void> reloadConflict(OpenDocument document) async {
    final diskSnapshot = document.conflictSnapshot;
    if (diskSnapshot == null) {
      return;
    }
    document.snapshot = diskSnapshot;
    _applyDiskText(
      document,
      diskSnapshot.text,
      selection: document.editorController.selection,
    );
    document.conflictSnapshot = null;
    document.failure = null;
    document.sourceMissing = false;
    document.saveStatus = DocumentSaveStatus.clean;
    document.notifyChanged();
  }

  Future<void> saveConflictCopy(OpenDocument document) async {
    final extension = p.extension(document.name);
    final stem = p.basenameWithoutExtension(document.name);
    final now = DateTime.now();
    final timestamp =
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}-'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    final initialText = document.chapterNumber == null
        ? document.editorController.text
        : ChapterTitleText.compose(
            document.chapterNumber!,
            ChapterTitleText.sanitizeForFilename(document.chapterTitleSubtitle),
            document.editorController.text,
            markdown: document.isMarkdown,
          );
    final entry = await service.createDocument(
      session,
      parentPath: p.dirname(document.relativePath) == '.'
          ? ''
          : p.dirname(document.relativePath),
      name: '$stem (冲突 $timestamp)$extension',
      format: document.format,
      initialText: initialText,
    );
    if (document.sourceMissing) {
      final version = document.editorController.buildSnapshot().version;
      document.editorController.markSaved(version);
      await closeDocument(document);
    } else {
      await reloadConflict(document);
    }
    _bumpTreeRevision();
    await openPath(entry.relativePath);
  }

  Future<void> persistSession() async {
    _sessionSaveTimer?.cancel();
    final states = _tabs.take(_maximumRestoredTabs).map((tab) {
      if (tab is DeferredDocument) {
        return tab.state;
      }
      final document = tab as OpenDocument;
      final selection = document.editorController.selection;
      final offset = document.scrollController.hasClients
          ? document.scrollController.offset
          : document.scrollController.initialScrollOffset;
      return WorkspaceDocumentState(
        relativePath: document.relativePath,
        selectionBase: selection.baseOffset,
        selectionExtent: selection.extentOffset,
        scrollOffset: offset,
      );
    }).toList();
    await service.saveSession(
      session,
      WorkspaceSessionSnapshot(
        documents: states,
        activePath: _activePath,
        expandedDirectoryPaths: _expandedDirectoryPaths(),
      ),
    );
  }

  Future<void> _openDocument(
    DocumentRef ref, {
    TextSelection? selection,
    double scrollOffset = 0,
    bool activate = true,
  }) async {
    final snapshot = await service.readDocument(session, ref);
    final document = _createOpenDocument(
      snapshot,
      selection: selection,
      scrollOffset: scrollOffset,
    );
    _tabs.add(document);
    if (activate) {
      _activePath = ref.relativePath;
      _selectedPath = ref.relativePath;
    }
    _scheduleSessionSave();
    _notify();
  }

  OpenDocument _createOpenDocument(
    DocumentSnapshot snapshot, {
    TextSelection? selection,
    double scrollOffset = 0,
  }) {
    // 章节文档（TXT 或 Markdown）把首行 `第N章 [副标题]`（MD 可带 `# `）拆为
    // 标题栏状态，编辑器只持有正文；非章节文档保持「编辑器持有完整正文」的旧行为。
    final parsed = ChapterTitleText.tryParse(snapshot.text);
    final controllerText = parsed == null
        ? snapshot.text
        : ChapterTitleText.bodyOf(snapshot.text);
    final LoreDocumentController controller =
        snapshot.ref.format == DocumentFormat.text
        ? LoreLargeTextController(text: controllerText)
        : LoreTextController(text: controllerText);
    if (selection != null) {
      controller.selection = TextSelection(
        baseOffset: selection.baseOffset.clamp(0, controllerText.length),
        extentOffset: selection.extentOffset.clamp(0, controllerText.length),
      );
    }
    final document = OpenDocument(
      snapshot: snapshot,
      editorController: controller,
      scrollController: ScrollController(
        initialScrollOffset: scrollOffset < 0 ? 0 : scrollOffset,
      ),
    );
    document.chapterNumber = parsed?.number;
    document.chapterTitleSubtitle = parsed?.subtitle ?? '';
    document.characterCount = controller.characterCount;
    var observedVersion = controller.editVersion;
    controller.addListener(() {
      if (_disposed) {
        return;
      }
      if (controller.editVersion != observedVersion) {
        observedVersion = controller.editVersion;
        _scheduleStatisticsUpdate(document);
        if (document.saveStatus != DocumentSaveStatus.conflict) {
          document.failure = null;
          document.saveStatus = controller.hasUnsavedChanges
              ? DocumentSaveStatus.dirty
              : DocumentSaveStatus.clean;
          if (controller.hasUnsavedChanges) {
            _scheduleAutoSave(document);
          }
        }
      }
      _scheduleSessionSave();
      document.notifyChanged();
    });
    document.scrollController.addListener(_scheduleSessionSave);
    return document;
  }

  Future<OpenDocument?> _loadDeferredDocument(DeferredDocument deferred) async {
    final index = _tabs.indexOf(deferred);
    if (index < 0) {
      return null;
    }
    try {
      final snapshot = await service.readDocument(
        session,
        DocumentRef(
          relativePath: deferred.relativePath,
          format: deferred.format,
        ),
      );
      final document = _createOpenDocument(
        snapshot,
        selection: TextSelection(
          baseOffset: deferred.state.selectionBase,
          extentOffset: deferred.state.selectionExtent,
        ),
        scrollOffset: deferred.state.scrollOffset,
      );
      _tabs[index] = document;
      deferred.dispose();
      _notify();
      return document;
    } on LibraryOperationException catch (error) {
      _tabs.removeAt(index);
      deferred.dispose();
      _reportFailure(error.failure);
      if (_activePath == deferred.relativePath) {
        _activePath = _tabs.firstOrNull?.relativePath;
      }
    }
    _notify();
    return null;
  }

  void _scheduleAutoSave(OpenDocument document) {
    document.saveTimer?.cancel();
    document.saveTimer = Timer(_autoSaveDelay, () {
      unawaited(saveDocument(document));
    });
  }

  void _scheduleStatisticsUpdate(OpenDocument document) {
    document.statisticsTimer?.cancel();
    document.statisticsTimer = Timer(_statisticsDelay, () {
      if (_disposed) {
        return;
      }
      final next = document.editorController.characterCount;
      final delta = next - document.characterCount;
      if (delta == 0) {
        return;
      }
      document.characterCount = next;
      document.notifyChanged();
      final progress = writingProgressRepository;
      if (progress != null) {
        final novelId = _novelIdForPath(document.relativePath);
        if (novelId != null) {
          unawaited(progress.addDelta(novelId, DateTime.now().toUtc(), delta));
        }
      }
    });
  }

  void _scheduleSessionSave() {
    if (!_initialized || _disposed) {
      return;
    }
    _sessionSaveTimer?.cancel();
    _sessionSaveTimer = Timer(_sessionSaveDelay, () {
      unawaited(persistSession());
    });
  }

  /// 处理文件变更事件中「影响已打开文档」的部分：为受影响文档安排冲突复检。
  /// 不处理目录树版本号与小说 reconcile（由控制器在调用前后编排）。
  void handleDocumentChange(
    DocumentChange change, {
    bool confirmMissingAsStructural = false,
  }) {
    final affectedDocuments = documents.where((document) {
      if (document.relativePath == change.relativePath) {
        return true;
      }
      return (change.type == DocumentChangeType.deleted ||
              change.type == DocumentChangeType.moved) &&
          p.isWithin(change.relativePath, document.relativePath);
    }).toList();
    if (affectedDocuments.isEmpty) {
      return;
    }
    for (final document in affectedDocuments) {
      _externalChangeTimers[document.relativePath]?.cancel();
      _externalChangeTimers[document.relativePath] = Timer(
        _externalChangeDelay,
        () => unawaited(
          _inspectExternalChange(
            document,
            confirmMissingAsStructural: confirmMissingAsStructural,
          ),
        ),
      );
    }
  }

  /// Rechecks open documents for backends that cannot provide change streams.
  Future<void> reconcileOpenDocuments() async {
    for (final document in List<OpenDocument>.of(documents)) {
      if (_disposed) {
        return;
      }
      await _inspectExternalChange(document);
    }
  }

  Future<void> _inspectExternalChange(
    OpenDocument document, {
    bool confirmMissingAsStructural = false,
  }) async {
    try {
      final diskSnapshot = await service.readDocument(
        session,
        document.snapshot.ref,
      );
      if (diskSnapshot.revision == document.snapshot.revision) {
        return;
      }
      if (document.hasUnsavedChanges ||
          document.saveStatus == DocumentSaveStatus.saving) {
        document.conflictSnapshot = diskSnapshot;
        document.sourceMissing = false;
        document.saveStatus = DocumentSaveStatus.conflict;
      } else {
        document.snapshot = diskSnapshot;
        _applyDiskText(
          document,
          diskSnapshot.text,
          selection: document.editorController.selection,
        );
        document.saveStatus = DocumentSaveStatus.clean;
      }
    } on LibraryOperationException catch (error) {
      _applyDocumentFailure(document, error.failure);
      if (confirmMissingAsStructural &&
          error.failure.code == LibraryFailureCode.notFound) {
        _confirmStructuralChange(document.relativePath);
      }
    }
    _notify();
  }

  void _applyDocumentFailure(OpenDocument document, LibraryFailure failure) {
    document.failure = failure;
    if (failure.code == LibraryFailureCode.notFound &&
        document.hasUnsavedChanges) {
      document.conflictSnapshot = null;
      document.sourceMissing = true;
      document.saveStatus = DocumentSaveStatus.conflict;
      return;
    }
    document.saveStatus = DocumentSaveStatus.error;
  }

  /// 重命名/移动后，把标签内缓存的旧路径重写到新路径（仅逻辑，不 notify）。
  void updatePathsAfterRename(String oldPath, String newPath) {
    for (final tab in _tabs) {
      if (tab is DeferredDocument) {
        final path = tab.relativePath;
        if (path != oldPath && !p.isWithin(oldPath, path)) {
          continue;
        }
        final suffix = path == oldPath ? '' : p.relative(path, from: oldPath);
        final updatedPath = suffix.isEmpty ? newPath : p.join(newPath, suffix);
        tab.state = WorkspaceDocumentState(
          relativePath: updatedPath,
          selectionBase: tab.state.selectionBase,
          selectionExtent: tab.state.selectionExtent,
          scrollOffset: tab.state.scrollOffset,
        );
        if (_activePath == path) {
          _activePath = updatedPath;
        }
        continue;
      }
      final document = tab as OpenDocument;
      final path = document.relativePath;
      if (path != oldPath && !p.isWithin(oldPath, path)) {
        continue;
      }
      final suffix = path == oldPath ? '' : p.relative(path, from: oldPath);
      final updatedPath = suffix.isEmpty ? newPath : p.join(newPath, suffix);
      document.snapshot = DocumentSnapshot(
        ref: document.snapshot.ref.copyWith(relativePath: updatedPath),
        text: document.snapshot.text,
        encoding: document.snapshot.encoding,
        lineEnding: document.snapshot.lineEnding,
        revision: document.snapshot.revision,
      );
      if (_activePath == path) {
        _activePath = updatedPath;
      }
    }
  }

  /// 应用删除结果中「关闭被删路径下的标签 + 清理选择」的部分（仅逻辑 +
  /// session 保存，不 notify、不动 treeRevision——由控制器编排）。
  void applyDeletionPathChanges(List<PathChange> pathChanges) {
    final removedPaths = pathChanges.map((change) => change.oldPath);
    if (_selectedPath != null) {
      final selectedRemoved = removedPaths.any(
        (removed) =>
            _selectedPath == removed || p.isWithin(removed, _selectedPath!),
      );
      if (selectedRemoved) {
        _selectedEntry = null;
        _selectedPath = null;
      }
    }
    final hasOpenTabsBeneathRemoved = _tabs.any((tab) {
      for (final removed in removedPaths) {
        if (tab.relativePath == removed ||
            p.isWithin(removed, tab.relativePath)) {
          return true;
        }
      }
      return false;
    });
    if (hasOpenTabsBeneathRemoved) {
      _tabs.removeWhere((tab) {
        for (final removed in removedPaths) {
          if (tab.relativePath == removed ||
              p.isWithin(removed, tab.relativePath)) {
            tab.dispose();
            return true;
          }
        }
        return false;
      });
      if (_activePath != null) {
        final stillOpen = _tabForPath(_activePath) != null;
        if (!stillOpen) {
          _activePath = _tabs.firstOrNull?.relativePath;
          _selectedPath = _activePath;
        }
      }
    }
    _scheduleSessionSave();
  }

  OpenDocument? _documentForPath(String? relativePath) {
    if (relativePath == null) {
      return null;
    }
    for (final document in documents) {
      if (document.relativePath == relativePath) {
        return document;
      }
    }
    return null;
  }

  WorkspaceTab? _tabForPath(String? relativePath) {
    if (relativePath == null) {
      return null;
    }
    for (final tab in _tabs) {
      if (tab.relativePath == relativePath) {
        return tab;
      }
    }
    return null;
  }

  DocumentFormat? _formatForPath(String relativePath) {
    return switch (p.extension(relativePath).toLowerCase()) {
      '.txt' => DocumentFormat.text,
      '.md' => DocumentFormat.markdown,
      _ => null,
    };
  }

  void dispose() {
    _disposed = true;
    _sessionSaveTimer?.cancel();
    for (final timer in _externalChangeTimers.values) {
      timer.cancel();
    }
    for (final tab in _tabs) {
      tab.dispose();
    }
  }
}
