import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('keeps cached entries visible while refreshing', (tester) async {
    final refresh = Completer<List<LibraryEntry>>();
    final repository = _QueuedWorkspaceRepository([
      Future.value(const [
        LibraryEntry(
          name: '卷一',
          relativePath: '卷一',
          type: LibraryEntryType.directory,
        ),
      ]),
      refresh.future,
    ]);
    final controller = _controller(session, repository);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_tree(controller, reloadToken: 0));
    await tester.pump();
    expect(find.text('卷一'), findsOneWidget);

    await tester.pumpWidget(_tree(controller, reloadToken: 1));
    await tester.pump();

    expect(find.text('卷一'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    refresh.complete(const [
      LibraryEntry(
        name: '卷一',
        relativePath: '卷一',
        type: LibraryEntryType.directory,
      ),
      LibraryEntry(
        name: '资料.md',
        relativePath: '资料.md',
        type: LibraryEntryType.markdownFile,
      ),
    ]);
    await tester.pump();
    await tester.pump();

    expect(find.text('资料.md'), findsOneWidget);
  });

  testWidgets('restores expanded directories from controller state', (
    tester,
  ) async {
    final repository = _PathWorkspaceRepository({
      '': const [
        LibraryEntry(
          name: '卷一',
          relativePath: '卷一',
          type: LibraryEntryType.directory,
        ),
      ],
      '卷一': const [
        LibraryEntry(
          name: '第一章.md',
          relativePath: '卷一/第一章.md',
          type: LibraryEntryType.markdownFile,
        ),
      ],
    });
    final controller = _controller(session, repository);
    controller.setDirectoryExpanded('卷一', true);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_tree(controller, reloadToken: 0));
    await tester.pump();
    await tester.pump();

    expect(find.text('第一章.md'), findsOneWidget);
  });

  testWidgets('expands directories and selects tree entries from custom rows', (
    tester,
  ) async {
    final repository = _PathWorkspaceRepository({
      '': const [
        LibraryEntry(
          name: '卷一',
          relativePath: '卷一',
          type: LibraryEntryType.directory,
        ),
      ],
      '卷一': const [
        LibraryEntry(
          name: '第一章.md',
          relativePath: '卷一/第一章.md',
          type: LibraryEntryType.markdownFile,
        ),
      ],
    });
    final controller = _controller(session, repository);
    final selected = <LibraryEntry>[];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _tree(controller, reloadToken: 0, onSelected: selected.add),
    );
    await tester.pump();

    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    await tester.tap(find.text('卷一'));
    await tester.pump();
    await tester.pump();

    expect(selected.single.relativePath, '卷一');
    expect(find.text('第一章.md'), findsOneWidget);

    await tester.tap(find.text('第一章.md'));
    expect(selected.last.relativePath, '卷一/第一章.md');
  });

  testWidgets('exposes expansion semantics and supports keyboard activation', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repository = _PathWorkspaceRepository({
      '': const [
        LibraryEntry(
          name: '卷一',
          relativePath: '卷一',
          type: LibraryEntryType.directory,
        ),
      ],
      '卷一': const [
        LibraryEntry(
          name: '第一章.md',
          relativePath: '卷一/第一章.md',
          type: LibraryEntryType.markdownFile,
        ),
      ],
    });
    final controller = _controller(session, repository);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_tree(controller, reloadToken: 0));
    await tester.pump();

    final collapsedSemantics = tester.getSemantics(find.text('卷一'));
    expect(
      collapsedSemantics,
      matchesSemantics(
        label: '卷一',
        isButton: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
        hasSelectedState: true,
        hasExpandedState: true,
        isExpanded: false,
      ),
    );
    expect(
      collapsedSemantics.getSemanticsData().hasAction(SemanticsAction.expand),
      isTrue,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();

    expect(find.text('第一章.md'), findsOneWidget);
    final expandedSemantics = tester.getSemantics(find.text('卷一'));
    expect(
      expandedSemantics,
      matchesSemantics(
        label: '卷一',
        isButton: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
        isFocused: true,
        hasSelectedState: true,
        hasExpandedState: true,
        isExpanded: true,
      ),
    );
    expect(
      expandedSemantics.getSemanticsData().hasAction(SemanticsAction.collapse),
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
}) {
  return MaterialApp(
    home: Scaffold(
      body: WorkspaceDirectory(
        controller: controller,
        relativePath: '',
        selectedPath: null,
        reloadToken: reloadToken,
        onSelected: onSelected ?? (_) {},
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

final class _QueuedWorkspaceRepository extends _WorkspaceRepository {
  _QueuedWorkspaceRepository(this.responses);

  final List<Future<List<LibraryEntry>>> responses;

  @override
  Future<List<LibraryEntry>> listChildren(
    LibraryAccess access, {
    String relativePath = '',
  }) {
    return responses.removeAt(0);
  }
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
