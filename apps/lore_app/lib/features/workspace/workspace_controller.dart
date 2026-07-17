import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_editor/lore_editor.dart';
import 'package:path/path.dart' as p;

enum DocumentSaveStatus { clean, dirty, saving, conflict, error }

sealed class WorkspaceTab extends ChangeNotifier {
  String get relativePath;

  String get name => p.basename(relativePath);

  bool get hasUnsavedChanges;
}

final class DeferredDocument extends WorkspaceTab {
  DeferredDocument({required this.state, required this.format});

  WorkspaceDocumentState state;
  final DocumentFormat format;

  @override
  String get relativePath => state.relativePath;

  @override
  bool get hasUnsavedChanges => false;
}

final class OpenDocument extends WorkspaceTab {
  OpenDocument({
    required this.snapshot,
    required this.editorController,
    required this.scrollController,
  });

  DocumentSnapshot snapshot;
  final LoreTextController editorController;
  final ScrollController scrollController;
  DocumentSaveStatus saveStatus = DocumentSaveStatus.clean;
  DocumentSnapshot? conflictSnapshot;
  LibraryFailure? failure;
  bool sourceMissing = false;
  bool showPreview = false;
  Timer? saveTimer;
  Future<bool>? saveFuture;

  @override
  String get relativePath => snapshot.ref.relativePath;

  DocumentFormat get format => snapshot.ref.format;

  bool get isMarkdown => format == DocumentFormat.markdown;

  @override
  bool get hasUnsavedChanges => editorController.hasUnsavedChanges;

  void notifyChanged() => notifyListeners();

  @override
  void dispose() {
    saveTimer?.cancel();
    editorController.dispose();
    scrollController.dispose();
    super.dispose();
  }
}

final class WorkspaceController extends ChangeNotifier {
  WorkspaceController({required this.session, required this.service});

  static const _autoSaveDelay = Duration(milliseconds: 800);
  static const _sessionSaveDelay = Duration(milliseconds: 500);
  static const _externalChangeDelay = Duration(milliseconds: 180);
  static const _maximumRestoredTabs = 20;

  final LibrarySession session;
  final LibraryWorkspaceService service;
  final List<WorkspaceTab> _tabs = [];
  final Map<String, Timer> _externalChangeTimers = {};

  StreamSubscription<DocumentChange>? _changeSubscription;
  Timer? _sessionSaveTimer;
  String? _activePath;
  String? _selectedPath;
  bool _initialized = false;
  bool _disposed = false;
  int _treeRevision = 0;
  LibraryFailure? _workspaceFailure;

  List<WorkspaceTab> get tabs => List.unmodifiable(_tabs);

  List<OpenDocument> get documents => _tabs.whereType<OpenDocument>().toList();

  String? get activePath => _activePath;

  String? get selectedPath => _selectedPath;

  int get treeRevision => _treeRevision;

  LibraryFailure? get workspaceFailure => _workspaceFailure;

  bool get initialized => _initialized;

  OpenDocument? get activeDocument => _documentForPath(_activePath);

  Future<void> initialize() async {
    if (_initialized) {
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
    _changeSubscription = service
        .watchDocuments(session)
        .listen(_handleDocumentChange, onError: (_) {});
    _initialized = true;
    _notify();
    final activeTab = _tabForPath(_activePath);
    if (activeTab != null) {
      await activateTab(activeTab);
    }
  }

  void selectPath(String relativePath) {
    _selectedPath = relativePath;
    _notify();
  }

  void dismissWorkspaceFailure() {
    _workspaceFailure = null;
    _notify();
  }

  Future<List<LibraryEntry>> listChildren({String relativePath = ''}) {
    return service.listChildren(session, relativePath: relativePath);
  }

  Future<void> openPath(String relativePath) async {
    final format = _formatForPath(relativePath);
    if (format == null) {
      selectPath(relativePath);
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

  Future<LibraryEntry> createDirectory({
    required String parentPath,
    required String name,
  }) async {
    final entry = await service.createDirectory(
      session,
      parentPath: parentPath,
      name: name,
    );
    _selectedPath = entry.relativePath;
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
    _treeRevision += 1;
    await openPath(entry.relativePath);
    return entry;
  }

  Future<LibraryEntry> renameSelected(String newName) async {
    final sourcePath = _selectedPath;
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
    _updatePathsAfterRename(sourcePath, entry.relativePath);
    _selectedPath = entry.relativePath;
    _treeRevision += 1;
    _scheduleSessionSave();
    _notify();
    return entry;
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
    _scheduleSessionSave();
    _notify();
  }

  void setPreview(OpenDocument document, bool showPreview) {
    if (!document.isMarkdown || document.showPreview == showPreview) {
      return;
    }
    document.showPreview = showPreview;
    document.notifyChanged();
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
      document.saveStatus = DocumentSaveStatus.saving;
      document.failure = null;
      document.notifyChanged();
      try {
        final result = await service.saveDocument(
          session,
          original: document.snapshot,
          text: editorSnapshot.text,
        );
        switch (result) {
          case DocumentSaveSuccess(:final snapshot):
            document.snapshot = snapshot;
            document.sourceMissing = false;
            document.editorController.markSaved(editorSnapshot.version);
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
    document.editorController.replaceFromDisk(
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
    final entry = await service.createDocument(
      session,
      parentPath: p.dirname(document.relativePath) == '.'
          ? ''
          : p.dirname(document.relativePath),
      name: '$stem (冲突 $timestamp)$extension',
      format: document.format,
      initialText: document.editorController.text,
    );
    if (document.sourceMissing) {
      final version = document.editorController.buildSnapshot().version;
      document.editorController.markSaved(version);
      await closeDocument(document);
    } else {
      await reloadConflict(document);
    }
    _treeRevision += 1;
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
      WorkspaceSessionSnapshot(documents: states, activePath: _activePath),
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
    final controller = LoreTextController(text: snapshot.text);
    if (selection != null) {
      controller.selection = TextSelection(
        baseOffset: selection.baseOffset.clamp(0, snapshot.text.length),
        extentOffset: selection.extentOffset.clamp(0, snapshot.text.length),
      );
    }
    final document = OpenDocument(
      snapshot: snapshot,
      editorController: controller,
      scrollController: ScrollController(
        initialScrollOffset: scrollOffset < 0 ? 0 : scrollOffset,
      ),
    );
    var observedVersion = controller.editVersion;
    controller.addListener(() {
      if (_disposed) {
        return;
      }
      if (controller.editVersion != observedVersion) {
        observedVersion = controller.editVersion;
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
      _workspaceFailure = error.failure;
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

  void _scheduleSessionSave() {
    if (!_initialized || _disposed) {
      return;
    }
    _sessionSaveTimer?.cancel();
    _sessionSaveTimer = Timer(_sessionSaveDelay, () {
      unawaited(persistSession());
    });
  }

  void _handleDocumentChange(DocumentChange change) {
    final treeChanged = change.type != DocumentChangeType.modified;
    if (treeChanged) {
      _treeRevision += 1;
    }
    final affectedDocuments = documents.where((document) {
      if (document.relativePath == change.relativePath) {
        return true;
      }
      return (change.type == DocumentChangeType.deleted ||
              change.type == DocumentChangeType.moved) &&
          p.isWithin(change.relativePath, document.relativePath);
    }).toList();
    if (affectedDocuments.isEmpty) {
      if (treeChanged) {
        _notify();
      }
      return;
    }
    for (final document in affectedDocuments) {
      _externalChangeTimers[document.relativePath]?.cancel();
      _externalChangeTimers[document.relativePath] = Timer(
        _externalChangeDelay,
        () => unawaited(_inspectExternalChange(document)),
      );
    }
    if (treeChanged) {
      _notify();
    }
  }

  Future<void> _inspectExternalChange(OpenDocument document) async {
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
        document.editorController.replaceFromDisk(
          diskSnapshot.text,
          selection: document.editorController.selection,
        );
        document.saveStatus = DocumentSaveStatus.clean;
      }
    } on LibraryOperationException catch (error) {
      _applyDocumentFailure(document, error.failure);
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

  void _updatePathsAfterRename(String oldPath, String newPath) {
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

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _sessionSaveTimer?.cancel();
    for (final timer in _externalChangeTimers.values) {
      timer.cancel();
    }
    unawaited(_changeSubscription?.cancel());
    for (final tab in _tabs) {
      tab.dispose();
    }
    super.dispose();
  }
}
