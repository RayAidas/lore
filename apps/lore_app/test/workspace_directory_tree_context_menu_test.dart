import 'dart:ui' show PointerDeviceKind, SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter_test/flutter_test.dart';
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
