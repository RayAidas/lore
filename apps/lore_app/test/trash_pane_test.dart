import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_app/features/workspace/trash_pane.dart';
import 'package:lore_app/features/workspace/workspace_controller.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_ui/lore_ui.dart';

void main() {
  testWidgets('trash dialog is wider, shorter, and presents compact rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final item = TrashItem(
      token: 'trash-1',
      type: TrashItemType.chapter,
      originalRelativePath: '长夜行/正文/第一卷/第一章.md',
      trashRelativePath: '.lore/trash/trash-1/第一章.md',
      deletedAt: DateTime.utc(2026, 7, 21, 10, 30),
      restorable: true,
    );
    final trashRepository = _FakeTrashRepository([item]);
    final workspaceRepository = _UnusedWorkspaceRepository();
    final controller = WorkspaceController(
      session: LibrarySession(
        access: const LibraryAccess(
          token: '/tmp/library',
          displayPath: '/tmp/library',
          isPending: false,
        ),
        metadata: LibraryMetadata(
          schemaVersion: 1,
          id: const LibraryId('11111111-1111-4111-8111-111111111111'),
          createdAt: DateTime.utc(2026, 7, 21),
          updatedAt: DateTime.utc(2026, 7, 21),
        ),
      ),
      service: LibraryWorkspaceService(
        treeRepository: workspaceRepository,
        documentRepository: workspaceRepository,
        sessionRepository: _UnusedWorkspaceSessionRepository(),
      ),
      trashRepository: trashRepository,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: LoreTheme.light(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showTrashPanel(context, controller),
            child: const Text('打开回收站'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开回收站'));
    await tester.pumpAndSettle();

    final panelSize = tester.getSize(find.byKey(const ValueKey('lore-panel')));
    expect(panelSize.width, closeTo(680, 1));
    expect(panelSize.height, lessThanOrEqualTo(612));
    expect(find.text('第一章.md'), findsOneWidget);
    expect(find.textContaining('长夜行/正文/第一卷'), findsOneWidget);
    expect(find.text('恢复'), findsOneWidget);
    expect(find.byTooltip('永久删除'), findsOneWidget);
    expect(find.text('清空回收站'), findsOneWidget);
    expect(find.text('恢复或彻底删除已移除的内容'), findsNothing);

    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    expect(trashRepository.restoreCount, 1);
  });
}

final class _FakeTrashRepository implements TrashRepository {
  _FakeTrashRepository(this.items);

  final List<TrashItem> items;
  int restoreCount = 0;

  @override
  Future<void> empty(LibraryAccess access) async {}

  @override
  Future<List<TrashItem>> listItems(LibraryAccess access) async => items;

  @override
  Future<void> purge(
    LibraryAccess access, {
    required String trashToken,
  }) async {}

  @override
  Future<TrashItem> restore(
    LibraryAccess access, {
    required String trashToken,
    RestoreConflictStrategy strategy = RestoreConflictStrategy.rename,
  }) async {
    restoreCount += 1;
    return items.single;
  }
}

final class _UnusedWorkspaceRepository
    implements LibraryTreeRepository, DocumentRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

final class _UnusedWorkspaceSessionRepository
    implements WorkspaceSessionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
