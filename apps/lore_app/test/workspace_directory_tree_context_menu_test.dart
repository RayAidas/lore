import 'dart:ui' show PointerDeviceKind, SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_app/features/workspace/library_sidebar.dart';
import 'package:lore_app/features/workspace/workspace_controller.dart';
import 'package:lore_app/features/workspace/workspace_directory_tree.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';

void main() {
  final session = LibrarySession(
    access: const LibraryAccess(
      token: '/tmp/library',
      displayPath: '/tmp/library',
      isPending: false,
    ),
    metadata: LibraryMetadata(
      schemaVersion: 1,
      id: const LibraryId('11111111-1111-4111-8111-111111111111'),
      createdAt: DateTime.utc(2026, 7, 17),
      updatedAt: DateTime.utc(2026, 7, 17),
    ),
  );

  testWidgets('secondary tap on a file invokes onContextMenu with the entry', (
    tester,
  ) async {
    LibraryEntry? receivedEntry;
    Offset? receivedPosition;
    final repository = _PathWorkspaceRepository({
      '': const [
        LibraryEntry(
          name: '笔记.txt',
          relativePath: '笔记.txt',
          type: LibraryEntryType.textFile,
        ),
      ],
    });
    final controller = _controller(session, repository);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _tree(
        controller,
        reloadToken: 0,
        onContextMenu: (entry, position) {
          receivedEntry = entry;
          receivedPosition = position;
        },
      ),
    );
    await tester.pump();
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('笔记')),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(receivedEntry, isNotNull);
    expect(receivedEntry!.relativePath, '笔记.txt');
    expect(receivedPosition, isNotNull);
  });

  testWidgets('long press on a file invokes onContextMenu (mobile)', (
    tester,
  ) async {
    LibraryEntry? receivedEntry;
    final repository = _PathWorkspaceRepository({
      '': const [
        LibraryEntry(
          name: '笔记.txt',
          relativePath: '笔记.txt',
          type: LibraryEntryType.textFile,
        ),
      ],
    });
    final controller = _controller(session, repository);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _tree(
        controller,
        reloadToken: 0,
        onContextMenu: (entry, _) => receivedEntry = entry,
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.longPress(find.text('笔记'));
    await tester.pumpAndSettle();

    expect(receivedEntry, isNotNull);
    expect(receivedEntry!.relativePath, '笔记.txt');
  });

  testWidgets('secondary tap on a directory invokes onContextMenu', (
    tester,
  ) async {
    LibraryEntry? receivedEntry;
    final repository = _PathWorkspaceRepository({
      '': const [
        LibraryEntry(
          name: '资料',
          relativePath: '资料',
          type: LibraryEntryType.directory,
        ),
      ],
    });
    final controller = _controller(session, repository);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _tree(
        controller,
        reloadToken: 0,
        onContextMenu: (entry, _) => receivedEntry = entry,
      ),
    );
    await tester.pump();
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('资料')),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(receivedEntry, isNotNull);
    expect(receivedEntry!.isDirectory, isTrue);
    expect(receivedEntry!.relativePath, '资料');
  });

  testWidgets('secondary tap does not trigger onSelected', (tester) async {
    final selected = <LibraryEntry>[];
    final repository = _PathWorkspaceRepository({
      '': const [
        LibraryEntry(
          name: '笔记.txt',
          relativePath: '笔记.txt',
          type: LibraryEntryType.textFile,
        ),
      ],
    });
    final controller = _controller(session, repository);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _tree(
        controller,
        reloadToken: 0,
        onSelected: selected.add,
        onContextMenu: (_, _) {},
      ),
    );
    await tester.pump();
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('笔记')),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(selected, isEmpty);
  });

  testWidgets('primary tap immediately after a secondary tap still selects '
      '(right-click does not swallow the next left-click)', (tester) async {
    // 回归：右键后 _secondaryArmed 会被置位，若无 primary-down 复位，
    // 紧接着的第一次左键会被误判为右键残留而被吞掉。
    final selected = <LibraryEntry>[];
    final repository = _PathWorkspaceRepository({
      '': const [
        LibraryEntry(
          name: '笔记.txt',
          relativePath: '笔记.txt',
          type: LibraryEntryType.textFile,
        ),
      ],
    });
    final controller = _controller(session, repository);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _tree(
        controller,
        reloadToken: 0,
        onSelected: selected.add,
        onContextMenu: (_, _) {},
      ),
    );
    await tester.pump();
    await tester.pump();

    final secondary = await tester.startGesture(
      tester.getCenter(find.text('笔记')),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await secondary.up();
    await tester.pumpAndSettle();

    await tester.tap(find.text('笔记'));
    await tester.pump();

    expect(selected, hasLength(1));
    expect(selected.single.relativePath, '笔记.txt');
  });

  testWidgets('row exposes long-press semantics only when context menu wired', (
    tester,
  ) async {
    final repository = _PathWorkspaceRepository({
      '': const [
        LibraryEntry(
          name: '笔记.txt',
          relativePath: '笔记.txt',
          type: LibraryEntryType.textFile,
        ),
      ],
    });
    final controller = _controller(session, repository);
    addTearDown(controller.dispose);
    final semantics = tester.ensureSemantics();

    // 无上下文菜单回调：InkWell 不注册 long-press，行不应暴露该语义动作。
    await tester.pumpWidget(_tree(controller, reloadToken: 0));
    await tester.pump();
    await tester.pump();
    expect(
      tester
          .getSemantics(find.text('笔记'))
          .getSemanticsData()
          .hasAction(SemanticsAction.longPress),
      isFalse,
    );

    // 注入上下文菜单回调：InkWell 注册 long-press，行应暴露该语义动作，
    // 让无障碍用户可触发菜单。
    await tester.pumpWidget(
      _tree(controller, reloadToken: 0, onContextMenu: (_, _) {}),
    );
    await tester.pump();
    await tester.pump();
    expect(
      tester
          .getSemantics(find.text('笔记'))
          .getSemanticsData()
          .hasAction(SemanticsAction.longPress),
      isTrue,
    );
    semantics.dispose();
  });

  // 以下两个用例走真实的 LibrarySidebar（而非直接驱动 WorkspaceDirectory），
  // 专门守护"右键不应切换中间视图"的修复：novel/body/volume 跳过 selectEntry，
  // 其余条目仍同步选中。

  testWidgets('right-click a novel entry does not select it (no view switch)', (
    tester,
  ) async {
    final repository = _PathWorkspaceRepository({
      '': const [
        LibraryEntry(
          name: '我的小说',
          relativePath: '我的小说',
          type: LibraryEntryType.directory,
          semanticKind: LibraryEntrySemanticKind.novel,
          novelId: 'n1',
        ),
      ],
    });
    final controller = _controller(session, repository);
    addTearDown(controller.dispose);
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: LibrarySidebar(
              controller: controller,
              displayPath: '/tmp/library',
              onSelectLibrary: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(controller.selectedPath, isNull);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('我的小说')),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pump();

    // 右键小说目录不应改变选中——否则中间区域会被切到结构面板。
    expect(controller.selectedPath, isNull);
  });

  testWidgets('right-click a plain file still selects it (no view switch)', (
    tester,
  ) async {
    final repository = _PathWorkspaceRepository({
      '': const [
        LibraryEntry(
          name: '笔记.txt',
          relativePath: '笔记.txt',
          type: LibraryEntryType.textFile,
        ),
      ],
    });
    final controller = _controller(session, repository);
    addTearDown(controller.dispose);
    await controller.initialize();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: LibrarySidebar(
              controller: controller,
              displayPath: '/tmp/library',
              onSelectLibrary: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('笔记')),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pump();

    // 散文件右键仍同步选中（供重命名/删除使用），且其选中不会切走视图。
    expect(controller.selectedPath, '笔记.txt');
  });
}

WorkspaceController _controller(
  LibrarySession session,
  _WorkspaceRepository repository,
) {
  return WorkspaceController(
    session: session,
    service: LibraryWorkspaceService(
      treeRepository: repository,
      documentRepository: repository,
      sessionRepository: _MemorySessionRepository(),
    ),
  );
}

Widget _tree(
  WorkspaceController controller, {
  required int reloadToken,
  ValueChanged<LibraryEntry>? onSelected,
  ContextMenuCallback? onContextMenu,
}) {
  return MaterialApp(
    home: Scaffold(
      body: WorkspaceDirectory(
        controller: controller,
        relativePath: '',
        selectedPath: null,
        reloadToken: reloadToken,
        onSelected: onSelected ?? (_) {},
        onContextMenu: onContextMenu,
      ),
    ),
  );
}

abstract base class _WorkspaceRepository
    implements LibraryTreeRepository, DocumentRepository {
  @override
  Future<LibraryEntry> createDirectory(
    LibraryAccess access, {
    required String parentPath,
    required String name,
  }) => throw UnimplementedError();

  @override
  Future<LibraryEntry> createDocument(
    LibraryAccess access, {
    required String parentPath,
    required String name,
    required DocumentFormat format,
    String initialText = '',
  }) => throw UnimplementedError();

  @override
  Future<DeletionResult> deleteEntry(
    LibraryAccess access, {
    required String relativePath,
  }) => throw UnimplementedError();

  @override
  Future<DocumentSnapshot> readDocument(
    LibraryAccess access,
    DocumentRef ref,
  ) => throw UnimplementedError();

  @override
  Future<LibraryEntry> renameEntry(
    LibraryAccess access, {
    required String relativePath,
    required String newName,
  }) => throw UnimplementedError();

  @override
  Future<DocumentSaveResult> saveDocument(
    LibraryAccess access, {
    required DocumentSnapshot original,
    required String text,
  }) => throw UnimplementedError();

  @override
  Stream<DocumentChange> watchDocuments(LibraryAccess access) =>
      const Stream.empty();
}

final class _PathWorkspaceRepository extends _WorkspaceRepository {
  _PathWorkspaceRepository(this.entries);

  final Map<String, List<LibraryEntry>> entries;

  @override
  Future<List<LibraryEntry>> listChildren(
    LibraryAccess access, {
    String relativePath = '',
  }) async {
    return entries[relativePath] ?? const [];
  }
}

final class _MemorySessionRepository implements WorkspaceSessionRepository {
  @override
  Future<WorkspaceSessionSnapshot?> load(LibraryId libraryId) async => null;

  @override
  Future<void> save(
    LibraryId libraryId,
    WorkspaceSessionSnapshot snapshot,
  ) async {}
}
