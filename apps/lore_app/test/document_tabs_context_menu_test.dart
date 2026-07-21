import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_app/features/workspace/document_tabs.dart';
import 'package:lore_app/features/workspace/workspace_controller.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';

/// 锁定标签右键/长按上下文菜单的接入与防误触：
/// - 右键（secondary tap）与长按都触发 [DocumentTabs.onContextMenu]；
/// - 右键不激活标签（不切走当前 activePath）；
/// - 右键不会吞掉紧随其后的左键（_secondaryArmed 复位）。
void main() {
  const nameA = 'a.md';
  const nameB = 'b.md';

  final session = LibrarySession(
    access: const LibraryAccess(
      token: '/tmp/library',
      displayPath: '/tmp/library',
      isPending: false,
    ),
    metadata: LibraryMetadata(
      schemaVersion: 1,
      id: const LibraryId('33333333-3333-4333-8333-333333333333'),
      createdAt: DateTime.utc(2026, 7, 17),
      updatedAt: DateTime.utc(2026, 7, 17),
    ),
  );

  WorkspaceController buildController() {
    return WorkspaceController(
      session: session,
      service: LibraryWorkspaceService(
        treeRepository: _FakeRepo(),
        documentRepository: _FakeRepo(),
        sessionRepository: _NoopSessionRepo(),
      ),
    );
  }

  Widget harness(
    WorkspaceController controller, {
    TabContextMenuCallback? onContextMenu,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: DocumentTabs(
          controller: controller,
          onClose: (_) async {},
          onContextMenu: onContextMenu,
        ),
      ),
    );
  }

  testWidgets('secondary tap on a tab invokes onContextMenu with the tab', (
    tester,
  ) async {
    WorkspaceTab? received;
    Offset? position;
    final controller = buildController();
    addTearDown(controller.dispose);
    await controller.openPath(nameA);
    await controller.openPath(nameB);

    await tester.pumpWidget(
      harness(
        controller,
        onContextMenu: (tab, pos) {
          received = tab;
          position = pos;
        },
      ),
    );
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.text(nameA)),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(received, isNotNull);
    expect(received!.relativePath, nameA);
    expect(position, isNotNull);
  });

  testWidgets('long press on a tab invokes onContextMenu (mobile)', (
    tester,
  ) async {
    WorkspaceTab? received;
    final controller = buildController();
    addTearDown(controller.dispose);
    await controller.openPath(nameA);

    await tester.pumpWidget(
      harness(controller, onContextMenu: (tab, _) => received = tab),
    );
    await tester.pump();

    await tester.longPress(find.text(nameA));
    await tester.pumpAndSettle();

    expect(received, isNotNull);
    expect(received!.relativePath, nameA);
  });

  testWidgets('secondary tap does not activate the tab', (tester) async {
    final controller = buildController();
    addTearDown(controller.dispose);
    await controller.openPath(nameA);
    await controller.openPath(nameB);
    expect(controller.activePath, nameB);

    await tester.pumpWidget(harness(controller, onContextMenu: (_, _) {}));
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.text(nameA)),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    // 右键 a 不应把激活态从 b 切走。
    expect(controller.activePath, nameB);
  });

  testWidgets('primary tap immediately after a secondary tap still activates '
      '(right-click does not swallow the next left-click)', (tester) async {
    // 回归：右键后 _secondaryArmed 被置位，若无 primary-down 复位，
    // 紧接着的第一次左键会被误判为右键残留而被吞掉。
    final controller = buildController();
    addTearDown(controller.dispose);
    await controller.openPath(nameA);
    await controller.openPath(nameB);
    expect(controller.activePath, nameB);

    await tester.pumpWidget(harness(controller, onContextMenu: (_, _) {}));
    await tester.pump();

    final secondary = await tester.startGesture(
      tester.getCenter(find.text(nameA)),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await secondary.up();
    await tester.pumpAndSettle();

    await tester.tap(find.text(nameA));
    await tester.pump();

    expect(controller.activePath, nameA);
  });
}

final class _FakeRepo extends _BaseRepo {
  @override
  Future<List<LibraryEntry>> listChildren(
    LibraryAccess access, {
    String relativePath = '',
  }) async => const [];

  @override
  Future<DocumentSnapshot> readDocument(LibraryAccess access, DocumentRef ref) {
    return Future.value(
      DocumentSnapshot(
        ref: ref,
        text: '',
        encoding: TextEncoding.utf8,
        lineEnding: LineEnding.lf,
        revision: DocumentRevision('rev-${ref.relativePath}'),
      ),
    );
  }
}

abstract base class _BaseRepo
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

final class _NoopSessionRepo implements WorkspaceSessionRepository {
  @override
  Future<WorkspaceSessionSnapshot?> load(LibraryId libraryId) async => null;

  @override
  Future<void> save(
    LibraryId libraryId,
    WorkspaceSessionSnapshot snapshot,
  ) async {}
}
