import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lore_app/features/workspace/workspace_controller.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:path/path.dart' as p;

void main() {
  final metadata = LibraryMetadata(
    schemaVersion: 1,
    id: const LibraryId('11111111-1111-4111-8111-111111111111'),
    createdAt: DateTime.utc(2026, 7, 17),
    updatedAt: DateTime.utc(2026, 7, 17),
  );
  final session = LibrarySession(
    access: const LibraryAccess(
      token: '/tmp/library',
      displayPath: '/tmp/library',
      isPending: false,
    ),
    metadata: metadata,
  );

  testWidgets('auto-save persists the latest editor snapshot', (tester) async {
    final repository = _MemoryWorkspaceRepository(
      emitAtomicReplacementEventsOnSave: true,
    );
    final sessions = _MemorySessionRepository();
    final controller = WorkspaceController(
      session: session,
      service: LibraryWorkspaceService(
        treeRepository: repository,
        documentRepository: repository,
        sessionRepository: sessions,
      ),
    );
    addTearDown(() async {
      await repository.dispose();
    });

    await controller.initialize();
    await controller.openPath('章节.txt');
    final initialTreeRevision = controller.treeRevision;
    controller.activeDocument!.editorController.text = '第一版';
    await tester.pump(const Duration(milliseconds: 400));
    controller.activeDocument!.editorController.text = '第二版';
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    expect(repository.savedTexts, ['第二版']);
    expect(controller.activeDocument!.saveStatus, DocumentSaveStatus.clean);
    expect(controller.treeRevision, initialTreeRevision);
    controller.dispose();
  });

  testWidgets('chapter title is split from body and recombined on save', (
    tester,
  ) async {
    final repository = _MemoryWorkspaceRepository();
    final controller = WorkspaceController(
      session: session,
      service: LibraryWorkspaceService(
        treeRepository: repository,
        documentRepository: repository,
        sessionRepository: _MemorySessionRepository(),
      ),
    );
    addTearDown(repository.dispose);

    // 首行 `第1章` 被识别为标题：编辑器只持有正文，标题编号与副标题独立存储。
    repository.diskText = '第1章\n正文段';
    await controller.initialize();
    await controller.openPath('第1章.txt');

    final document = controller.activeDocument!;
    expect(document.chapterNumber, 1);
    expect(document.chapterTitleSubtitle, '');
    expect(document.editorController.text, '正文段');

    // 仅改副标题：锁定前缀不变，置脏并安排自动保存。
    controller.updateChapterTitleSubtitle(document, '甜蜜的家');
    expect(document.saveStatus, DocumentSaveStatus.dirty);

    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    // 落盘文本重组为「第1章 副标题\n正文」。
    expect(repository.savedTexts, ['第1章 甜蜜的家\n正文段']);
    expect(document.chapterNumber, 1);
    expect(document.chapterTitleSubtitle, '甜蜜的家');
    expect(document.saveStatus, DocumentSaveStatus.clean);
    controller.dispose();
  });

  testWidgets('subtitle edited during save is not lost', (tester) async {
    final repository = _MemoryWorkspaceRepository();
    final controller = WorkspaceController(
      session: session,
      service: LibraryWorkspaceService(
        treeRepository: repository,
        documentRepository: repository,
        sessionRepository: _MemorySessionRepository(),
      ),
    );
    addTearDown(repository.dispose);

    repository.diskText = '第1章\n正文段';
    // 让第一次 save 在 fake 内部门控挂起，便于在保存进行中再改副标题。
    final gate = Completer<void>();
    repository.saveGate = gate;
    await controller.initialize();
    await controller.openPath('第1章.txt');
    final document = controller.activeDocument!;

    controller.updateChapterTitleSubtitle(document, '甲');
    // 触发自动保存：_performSave 进入并在 gate 上挂起。
    await tester.pump(const Duration(milliseconds: 900));

    // 保存进行中再次改副标题（复现竞态）。
    controller.updateChapterTitleSubtitle(document, '乙');
    expect(document.titleDirty, isTrue);

    gate.complete(); // 放行第一次保存（写入「甲」）
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump();

    // 修复后：第一次保存发现副标题已变，循环再来一轮写入「乙」——两次都落盘。
    expect(document.chapterTitleSubtitle, '乙');
    expect(document.titleDirty, isFalse);
    expect(document.saveStatus, DocumentSaveStatus.clean);
    expect(repository.savedTexts, ['第1章 甲\n正文段', '第1章 乙\n正文段']);
    controller.dispose();
  });

  testWidgets('deleting and recreating an open document refreshes the tree', (
    tester,
  ) async {
    final repository = _MemoryWorkspaceRepository();
    final controller = WorkspaceController(
      session: session,
      service: LibraryWorkspaceService(
        treeRepository: repository,
        documentRepository: repository,
        sessionRepository: _MemorySessionRepository(),
      ),
    );
    addTearDown(repository.dispose);

    await controller.initialize();
    await controller.openPath('章节.txt');
    final initialTreeRevision = controller.treeRevision;
    repository.sourceMissing = true;
    repository.changes.add(
      const DocumentChange(
        relativePath: '章节.txt',
        type: DocumentChangeType.deleted,
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(controller.treeRevision, initialTreeRevision + 1);

    repository.sourceMissing = false;
    repository.changes.add(
      const DocumentChange(
        relativePath: '章节.txt',
        type: DocumentChangeType.created,
      ),
    );
    await tester.pump();

    expect(controller.treeRevision, initialTreeRevision + 2);
    controller.dispose();
  });

  testWidgets('external modification enters conflict without overwriting', (
    tester,
  ) async {
    final repository = _MemoryWorkspaceRepository();
    final controller = WorkspaceController(
      session: session,
      service: LibraryWorkspaceService(
        treeRepository: repository,
        documentRepository: repository,
        sessionRepository: _MemorySessionRepository(),
      ),
    );
    addTearDown(() async {
      await repository.dispose();
    });

    await controller.initialize();
    await controller.openPath('章节.txt');
    controller.activeDocument!.editorController.text = '本地修改';
    repository.diskText = '外部修改';
    repository.revision = 2;
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump();

    expect(repository.savedTexts, isEmpty);
    expect(controller.activeDocument!.saveStatus, DocumentSaveStatus.conflict);
    expect(controller.activeDocument!.editorController.text, '本地修改');
    controller.dispose();
  });

  testWidgets('foreground reconciliation reloads unwatched disk changes', (
    tester,
  ) async {
    final repository = _MemoryWorkspaceRepository();
    final controller = WorkspaceController(
      session: session,
      service: LibraryWorkspaceService(
        treeRepository: repository,
        documentRepository: repository,
        sessionRepository: _MemorySessionRepository(),
      ),
    );
    addTearDown(repository.dispose);

    await controller.initialize();
    await controller.openPath('章节.txt');
    repository.diskText = '前台恢复后的外部修改';
    repository.revision = 2;

    await controller.reconcileAfterForeground();
    await tester.pump();

    expect(controller.activeDocument!.editorController.text, '前台恢复后的外部修改');
    expect(controller.activeDocument!.saveStatus, DocumentSaveStatus.clean);
    controller.dispose();
  });

  testWidgets('restores open tabs and clamps the saved selection', (
    tester,
  ) async {
    final repository = _MemoryWorkspaceRepository();
    final sessions = _MemorySessionRepository(
      value: const WorkspaceSessionSnapshot(
        documents: [
          WorkspaceDocumentState(
            relativePath: '章节.txt',
            selectionBase: 99,
            selectionExtent: 99,
            scrollOffset: 12,
          ),
        ],
        activePath: '章节.txt',
      ),
    );
    final controller = WorkspaceController(
      session: session,
      service: LibraryWorkspaceService(
        treeRepository: repository,
        documentRepository: repository,
        sessionRepository: sessions,
      ),
    );
    addTearDown(() async {
      await repository.dispose();
    });

    await controller.initialize();

    expect(controller.documents, hasLength(1));
    expect(controller.activePath, '章节.txt');
    expect(
      controller.activeDocument!.editorController.selection.baseOffset,
      repository.diskText.length,
    );
    expect(controller.activeDocument!.scrollController.initialScrollOffset, 12);
    controller.dispose();
  });

  testWidgets('text edits notify only the affected document', (tester) async {
    final repository = _MemoryWorkspaceRepository();
    final controller = WorkspaceController(
      session: session,
      service: LibraryWorkspaceService(
        treeRepository: repository,
        documentRepository: repository,
        sessionRepository: _MemorySessionRepository(),
      ),
    );
    addTearDown(repository.dispose);
    await controller.initialize();
    await controller.openPath('章节.txt');
    var workspaceNotifications = 0;
    var documentNotifications = 0;
    controller.addListener(() => workspaceNotifications += 1);
    controller.activeDocument!.addListener(() => documentNotifications += 1);

    controller.activeDocument!.editorController.text = '新内容';

    expect(workspaceNotifications, 0);
    expect(documentNotifications, 1);
    controller.dispose();
  });

  testWidgets('missing source can be preserved as a conflict copy', (
    tester,
  ) async {
    final repository = _MemoryWorkspaceRepository();
    final controller = WorkspaceController(
      session: session,
      service: LibraryWorkspaceService(
        treeRepository: repository,
        documentRepository: repository,
        sessionRepository: _MemorySessionRepository(),
      ),
    );
    addTearDown(repository.dispose);
    await controller.initialize();
    await controller.openPath('章节.txt');
    final document = controller.activeDocument!;
    document.editorController.text = '未保存内容';
    repository.sourceMissing = true;

    expect(await controller.saveDocument(document), isFalse);
    expect(document.saveStatus, DocumentSaveStatus.conflict);
    expect(document.sourceMissing, isTrue);

    await controller.saveConflictCopy(document);

    expect(controller.tabs, hasLength(1));
    expect(controller.activeDocument!.name, contains('冲突'));
    expect(controller.activeDocument!.editorController.text, '未保存内容');
    controller.dispose();
  });

  testWidgets('restored tabs load only when activated', (tester) async {
    final repository = _MemoryWorkspaceRepository();
    final sessions = _MemorySessionRepository(
      value: const WorkspaceSessionSnapshot(
        documents: [
          WorkspaceDocumentState(
            relativePath: '一.txt',
            selectionBase: 0,
            selectionExtent: 0,
            scrollOffset: 0,
          ),
          WorkspaceDocumentState(
            relativePath: '二.txt',
            selectionBase: 0,
            selectionExtent: 0,
            scrollOffset: 0,
          ),
        ],
        activePath: '一.txt',
      ),
    );
    final controller = WorkspaceController(
      session: session,
      service: LibraryWorkspaceService(
        treeRepository: repository,
        documentRepository: repository,
        sessionRepository: sessions,
      ),
    );
    addTearDown(repository.dispose);

    await controller.initialize();

    expect(controller.tabs, hasLength(2));
    expect(controller.documents, hasLength(1));
    expect(repository.readPaths, ['一.txt']);

    await controller.activateTab(controller.tabs.last);

    expect(controller.documents, hasLength(2));
    expect(repository.readPaths, ['一.txt', '二.txt']);
    controller.dispose();
  });

  // ---- Phase 2 行为锁定：selection / rename / delete / treeRevision ----
  // 这些测试在抽取 WorkspaceTabsStore 前锁定跨切面行为，确保重构不破坏联动。

  WorkspaceController buildController(_MemoryWorkspaceRepository repository) {
    return WorkspaceController(
      session: session,
      service: LibraryWorkspaceService(
        treeRepository: repository,
        documentRepository: repository,
        sessionRepository: _MemorySessionRepository(),
      ),
    );
  }

  testWidgets('renaming the selected document follows the open tab', (
    tester,
  ) async {
    final repository = _MemoryWorkspaceRepository();
    final controller = buildController(repository);
    addTearDown(repository.dispose);
    await controller.initialize();
    await controller.openPath('章节.txt');
    final initialRevision = controller.treeRevision;

    await controller.renameSelected('新名.txt');

    expect(controller.activeDocument!.relativePath, '新名.txt');
    expect(controller.selectedPath, '新名.txt');
    expect(controller.selectedEntry!.name, '新名.txt');
    expect(controller.treeRevision, initialRevision + 1);
    controller.dispose();
  });

  testWidgets(
    'deleting the selected entry clears selection and bumps tree revision',
    (tester) async {
      final repository = _MemoryWorkspaceRepository();
      final controller = buildController(repository);
      addTearDown(repository.dispose);
      await controller.initialize();
      controller.selectPath('笔记.txt');
      final initialRevision = controller.treeRevision;

      await controller.deleteSelectedEntry();

      expect(controller.selectedPath, isNull);
      expect(controller.selectedEntry, isNull);
      expect(controller.treeRevision, initialRevision + 1);
      controller.dispose();
    },
  );

  testWidgets('deleting a directory closes the tabs beneath it', (
    tester,
  ) async {
    final repository = _MemoryWorkspaceRepository();
    final controller = buildController(repository);
    addTearDown(repository.dispose);
    await controller.initialize();
    await controller.openPath('卷一/章.txt');
    controller.selectPath('卷一');

    await controller.deleteSelectedEntry();

    expect(controller.tabs, isEmpty);
    expect(controller.activePath, isNull);
    controller.dispose();
  });

  testWidgets('creating a document selects and opens it', (tester) async {
    final repository = _MemoryWorkspaceRepository();
    final controller = buildController(repository);
    addTearDown(repository.dispose);
    await controller.initialize();
    final initialRevision = controller.treeRevision;

    await controller.createDocument(
      parentPath: '',
      name: '新文',
      format: DocumentFormat.text,
    );

    expect(controller.selectedPath, '新文.txt');
    expect(controller.activeDocument!.relativePath, '新文.txt');
    expect(controller.treeRevision, initialRevision + 1);
    controller.dispose();
  });

  testWidgets('restores and remaps expanded directory paths', (tester) async {
    final repository = _MemoryWorkspaceRepository();
    final sessions = _MemorySessionRepository(
      value: const WorkspaceSessionSnapshot(
        documents: [],
        activePath: null,
        expandedDirectoryPaths: ['卷一', '卷一/场景'],
      ),
    );
    final controller = WorkspaceController(
      session: session,
      service: LibraryWorkspaceService(
        treeRepository: repository,
        documentRepository: repository,
        sessionRepository: sessions,
      ),
    );
    addTearDown(repository.dispose);

    await controller.initialize();
    expect(controller.isDirectoryExpanded('卷一'), isTrue);
    expect(controller.isDirectoryExpanded('卷一/场景'), isTrue);

    controller.selectPath('卷一');
    await controller.renameSelected('新卷');
    await tester.pump(const Duration(milliseconds: 600));

    expect(controller.isDirectoryExpanded('卷一'), isFalse);
    expect(controller.isDirectoryExpanded('新卷'), isTrue);
    expect(controller.isDirectoryExpanded('新卷/场景'), isTrue);
    expect(
      sessions.value!.expandedDirectoryPaths,
      containsAll(['新卷', '新卷/场景']),
    );
    controller.dispose();
  });
}

final class _MemoryWorkspaceRepository
    implements LibraryTreeRepository, DocumentRepository {
  _MemoryWorkspaceRepository({this.emitAtomicReplacementEventsOnSave = false});

  final bool emitAtomicReplacementEventsOnSave;
  final changes = StreamController<DocumentChange>.broadcast();
  final savedTexts = <String>[];
  final readPaths = <String>[];
  final createdDocuments = <String, String>{};
  String diskText = '原文';
  int revision = 1;
  bool sourceMissing = false;

  /// 若非 null，下一次 [saveDocument] 会等待此 Completer 完成后再继续，
  /// 便于测试在保存进行中插入编辑（复现副标题保存竞态）。仅消费一次。
  Completer<void>? saveGate;

  Future<void> dispose() => changes.close();

  @override
  Future<LibraryEntry> createDirectory(
    LibraryAccess access, {
    required String parentPath,
    required String name,
  }) async {
    final relativePath = parentPath.isEmpty ? name : '$parentPath/$name';
    return LibraryEntry(
      name: name,
      relativePath: relativePath,
      type: LibraryEntryType.directory,
    );
  }

  @override
  Future<LibraryEntry> createDocument(
    LibraryAccess access, {
    required String parentPath,
    required String name,
    required DocumentFormat format,
    String initialText = '',
  }) async {
    final extension = format == DocumentFormat.text ? '.txt' : '.md';
    final fileName = name.endsWith(extension) ? name : '$name$extension';
    final relativePath = parentPath.isEmpty
        ? fileName
        : '$parentPath/$fileName';
    createdDocuments[relativePath] = initialText;
    return LibraryEntry(
      name: fileName,
      relativePath: relativePath,
      type: format == DocumentFormat.text
          ? LibraryEntryType.textFile
          : LibraryEntryType.markdownFile,
    );
  }

  @override
  Future<List<LibraryEntry>> listChildren(
    LibraryAccess access, {
    String relativePath = '',
  }) async {
    return const [];
  }

  @override
  Future<DocumentSnapshot> readDocument(
    LibraryAccess access,
    DocumentRef ref,
  ) async {
    readPaths.add(ref.relativePath);
    if (ref.relativePath == '章节.txt' && sourceMissing) {
      throw const LibraryOperationException(
        LibraryFailure(code: LibraryFailureCode.notFound, message: 'missing'),
      );
    }
    final text = createdDocuments[ref.relativePath] ?? diskText;
    return DocumentSnapshot(
      ref: ref,
      text: text,
      encoding: TextEncoding.utf8,
      lineEnding: LineEnding.lf,
      revision: DocumentRevision('revision-$revision'),
    );
  }

  @override
  Future<LibraryEntry> renameEntry(
    LibraryAccess access, {
    required String relativePath,
    required String newName,
  }) async {
    final dir = p.dirname(relativePath);
    final newPath = dir == '.' ? newName : '$dir/$newName';
    final type = p.extension(relativePath).toLowerCase() == '.txt'
        ? LibraryEntryType.textFile
        : LibraryEntryType.markdownFile;
    return LibraryEntry(name: newName, relativePath: newPath, type: type);
  }

  @override
  Future<DocumentSaveResult> saveDocument(
    LibraryAccess access, {
    required DocumentSnapshot original,
    required String text,
  }) async {
    if (original.ref.relativePath == '章节.txt' && sourceMissing) {
      throw const LibraryOperationException(
        LibraryFailure(code: LibraryFailureCode.notFound, message: 'missing'),
      );
    }
    final gate = saveGate;
    if (gate != null) {
      saveGate = null;
      await gate.future;
    }
    if (original.revision.value != 'revision-$revision') {
      return DocumentSaveConflict(await readDocument(access, original.ref));
    }
    savedTexts.add(text);
    if (createdDocuments.containsKey(original.ref.relativePath)) {
      createdDocuments[original.ref.relativePath] = text;
    } else {
      diskText = text;
    }
    revision += 1;
    if (emitAtomicReplacementEventsOnSave) {
      changes
        ..add(
          DocumentChange(
            relativePath: original.ref.relativePath,
            type: DocumentChangeType.deleted,
          ),
        )
        ..add(
          DocumentChange(
            relativePath: original.ref.relativePath,
            type: DocumentChangeType.created,
          ),
        );
    }
    return DocumentSaveSuccess(await readDocument(access, original.ref));
  }

  @override
  Stream<DocumentChange> watchDocuments(LibraryAccess access) {
    return changes.stream;
  }

  @override
  Future<DeletionResult> deleteEntry(
    LibraryAccess access, {
    required String relativePath,
  }) async {
    return DeletionResult(
      trashToken: 'trash-$relativePath',
      removedNodeIds: const [],
      pathChanges: [PathChange(oldPath: relativePath, newPath: '')],
    );
  }
}

final class _MemorySessionRepository implements WorkspaceSessionRepository {
  _MemorySessionRepository({this.value});

  WorkspaceSessionSnapshot? value;

  @override
  Future<WorkspaceSessionSnapshot?> load(LibraryId libraryId) async => value;

  @override
  Future<void> save(
    LibraryId libraryId,
    WorkspaceSessionSnapshot snapshot,
  ) async {
    value = snapshot;
  }
}
