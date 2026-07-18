import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';

import 'package:lore_app/features/workspace/document_tabs.dart';
import 'package:lore_app/features/workspace/workspace_controller.dart';

/// 锁定 [DocumentTabs] 的现代交互：
/// - 文件名以完整文本渲染，并提供整标签 hover 的 [Tooltip]；
/// - 标签随内容撑开（短名更窄、长名更宽），但不超过最大宽度；
/// - 激活标签暴露 selected 语义。
void main() {
  const shortName = '短.md';
  const longName =
      '这是一个非常非常非常非常非常非常非常长的小说章节文件名.md';

  final session = LibrarySession(
    access: const LibraryAccess(
      token: '/tmp/library',
      displayPath: '/tmp/library',
      isPending: false,
    ),
    metadata: LibraryMetadata(
      schemaVersion: 1,
      id: const LibraryId('22222222-2222-4222-8222-222222222222'),
      createdAt: DateTime.utc(2026, 7, 17),
      updatedAt: DateTime.utc(2026, 7, 17),
    ),
  );

  WorkspaceController buildController(_FakeRepository repository) {
    return WorkspaceController(
      session: session,
      service: LibraryWorkspaceService(
        treeRepository: repository,
        documentRepository: repository,
        sessionRepository: _NoopSessionRepository(),
      ),
    );
  }

  Widget harness(WorkspaceController controller) {
    return MaterialApp(
      home: Scaffold(
        body: DocumentTabs(
          controller: controller,
          onClose: (_) async {},
        ),
      ),
    );
  }

  testWidgets('renders each tab name with a full-name tooltip', (tester) async {
    final controller = buildController(_FakeRepository());
    addTearDown(controller.dispose);
    await controller.openPath(shortName);
    await controller.openPath(longName);

    await tester.pumpWidget(harness(controller));
    await tester.pump();

    expect(find.text(shortName), findsOneWidget);
    expect(find.text(longName), findsOneWidget);
    expect(find.byTooltip(shortName), findsOneWidget);
    expect(find.byTooltip(longName), findsOneWidget);
    expect(find.byTooltip('关闭'), findsNWidgets(2));
  });

  testWidgets('short tab is narrower than long tab; both stay within max width', (
    tester,
  ) async {
    final controller = buildController(_FakeRepository());
    addTearDown(controller.dispose);
    await controller.openPath(shortName);
    await controller.openPath(longName);

    await tester.pumpWidget(harness(controller));
    await tester.pump();

    final shortRect = tester.getRect(find.byTooltip(shortName));
    final longRect = tester.getRect(find.byTooltip(longName));

    // 随内容撑开：短名标签比长名标签窄。
    expect(shortRect.width, greaterThan(0));
    expect(shortRect.width, lessThan(longRect.width));
    // 有上限约束：长名标签不会无限撑开（maxWidth 220 + 左右内边距 14）。
    expect(longRect.width, lessThanOrEqualTo(240));
  });

  testWidgets('marks the active tab as selected for semantics', (tester) async {
    final handle = tester.ensureSemantics();
    final controller = buildController(_FakeRepository());
    addTearDown(controller.dispose);
    await controller.openPath(shortName);
    await controller.openPath(longName);

    await tester.pumpWidget(harness(controller));
    await tester.pump();

    // 最后打开的 longName 是激活标签。
    final active = tester
        .getSemantics(find.byTooltip(longName))
        .getSemanticsData();
    expect(active.flagsCollection.isSelected, Tristate.isTrue);

    final inactive = tester
        .getSemantics(find.byTooltip(shortName))
        .getSemanticsData();
    expect(inactive.flagsCollection.isSelected, Tristate.isFalse);

    handle.dispose();
  });

  testWidgets('invokes onClose with the tab when the close button is tapped', (
    tester,
  ) async {
    final closed = <WorkspaceTab>[];
    final controller = buildController(_FakeRepository());
    addTearDown(controller.dispose);
    await controller.openPath(shortName);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentTabs(
            controller: controller,
            onClose: (tab) async => closed.add(tab),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('关闭'));
    await tester.pump();

    expect(closed, hasLength(1));
    expect(closed.single.relativePath, shortName);
  });

  testWidgets('renders an empty bar with fixed height when there are no tabs', (
    tester,
  ) async {
    final controller = buildController(_FakeRepository());
    addTearDown(controller.dispose);

    await tester.pumpWidget(harness(controller));
    await tester.pump();

    expect(find.byType(ListView), findsNothing);
    expect(find.text(shortName), findsNothing);
    expect(tester.getSize(find.byType(DocumentTabs)).height, 38);
  });

  testWidgets('updates active styling when a tab is activated after mount', (
    tester,
  ) async {
    final controller = buildController(_FakeRepository());
    addTearDown(controller.dispose);
    await controller.openPath(shortName);
    await controller.openPath(longName);

    await tester.pumpWidget(harness(controller));
    await tester.pump();

    bool isSelected(String name) =>
        tester
            .getSemantics(find.byTooltip(name))
            .getSemanticsData()
            .flagsCollection
            .isSelected ==
        Tristate.isTrue;

    // 初始：最后打开的 longName 激活。
    expect(isSelected(longName), isTrue);
    expect(isSelected(shortName), isFalse);

    // 点击 shortName 后切换激活——依赖 DocumentTabs 自洽监听 controller。
    // 若移除外层 ListenableBuilder(controller)，此步不会更新 UI。
    await tester.tap(find.text(shortName));
    await tester.pump();

    expect(isSelected(shortName), isTrue);
    expect(isSelected(longName), isFalse);
  });
}

final class _FakeRepository extends _BaseRepository {
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

abstract base class _BaseRepository
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

final class _NoopSessionRepository implements WorkspaceSessionRepository {
  @override
  Future<WorkspaceSessionSnapshot?> load(LibraryId libraryId) async => null;

  @override
  Future<void> save(
    LibraryId libraryId,
    WorkspaceSessionSnapshot snapshot,
  ) async {}
}
