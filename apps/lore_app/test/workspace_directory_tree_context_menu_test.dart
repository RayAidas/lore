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

  testWidgets('right-click a novel entry offers plain create actions', (
    tester,
  ) async {
    // 回归：小说根目录右键菜单应提供「新建子文件夹/TXT/Markdown」——这些散
    // 文件落在 body（正文）子树之外，不参与卷/章结构扫描，安全；此前只有
    // 普通目录（semanticKind==null）有这三项，小说目录仅有「新建卷」。
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

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('我的小说')),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    // 结构化的「新建卷」保留，同时补齐散文件新建三项。
    expect(find.text('新建卷'), findsOneWidget);
    expect(find.text('新建子文件夹'), findsOneWidget);
    expect(find.text('新建 TXT'), findsOneWidget);
    expect(find.text('新建 Markdown'), findsOneWidget);
  });

  testWidgets(
    'toolbar new folder targets root even with a non-root selection',
    (tester) async {
      // 回归：顶部「新建」固定落书库根目录，不再读 selectedEntry。旧实现用
      // selectedEntry 推断 parentPath，选中非根目录时新建会被"吸"进该目录。
      const target = LibraryEntry(
        name: '资料',
        relativePath: '资料',
        type: LibraryEntryType.directory,
      );
      final repository = _RecordingRepository({
        '': const [target],
      });
      final controller = _controller(session, repository);
      addTearDown(controller.dispose);
      await controller.initialize();

      await tester.pumpWidget(_sidebar(controller));
      await tester.pump();
      await tester.pump();

      // 模拟选中非根目录——旧实现会据此把 parentPath 算成 '资料'。
      controller.selectEntry(target);
      await tester.pump();

      await tester.tap(find.byTooltip('新建'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建文件夹'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '新资料夹');
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();

      expect(repository.lastCreateDirectoryParent, '');
    },
  );

  testWidgets('right-click a novel creates a sub-folder inside the novel', (
    tester,
  ) async {
    // 回归：右键小说目录「新建子文件夹」应落在该小说目录内（散文件位于 body
    // 子树之外、不污染卷/章结构），而非落书库根目录——共享的 _createDirectory
    // 一旦固定 parentPath:''，右键入口也会被带偏，此用例锁住两条入口的区分。
    final repository = _RecordingRepository({
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

    await tester.pumpWidget(_sidebar(controller));
    await tester.pump();
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('我的小说')),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.tap(find.text('新建子文件夹'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '设定');
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(repository.lastCreateDirectoryParent, '我的小说');
  });

  testWidgets('right-click body or volume offers no plain create actions', (
    tester,
  ) async {
    // 回归：body 与卷目录禁止散文件新建——其下子目录会被结构扫描当成卷、
    // 文档会被当成章节。锁住"故意不补"的契约，防止 canCreatePlainChildren
    // 被无意放宽。
    final repository = _RecordingRepository({
      '': const [
        LibraryEntry(
          name: '正文',
          relativePath: '某小说/正文',
          type: LibraryEntryType.directory,
          semanticKind: LibraryEntrySemanticKind.body,
          semanticId: 'body1',
          novelId: 'n1',
        ),
        LibraryEntry(
          name: '第一卷',
          relativePath: '某小说/正文/第一卷',
          type: LibraryEntryType.directory,
          semanticKind: LibraryEntrySemanticKind.volume,
          semanticId: 'v1',
          novelId: 'n1',
        ),
      ],
    });
    final controller = _controller(session, repository);
    addTearDown(controller.dispose);
    await controller.initialize();

    await tester.pumpWidget(_sidebar(controller));
    await tester.pump();
    await tester.pump();

    Future<void> rightClick(String label) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.text(label)),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();
    }

    await rightClick('正文');
    expect(find.text('新建子文件夹'), findsNothing);
    expect(find.text('新建 TXT'), findsNothing);
    expect(find.text('新建 Markdown'), findsNothing);

    await rightClick('第一卷');
    expect(find.text('新建子文件夹'), findsNothing);
    expect(find.text('新建 TXT'), findsNothing);
    expect(find.text('新建 Markdown'), findsNothing);
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

Widget _sidebar(WorkspaceController controller) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: LibrarySidebar(
          controller: controller,
          displayPath: '/tmp/library',
          onSelectLibrary: () {},
        ),
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

/// 记录新建操作的 parentPath，用于回归「顶部按钮落根 / 右键目录落当前目录」。
final class _RecordingRepository extends _PathWorkspaceRepository {
  _RecordingRepository(super.entries);

  String? lastCreateDirectoryParent;
  String? lastCreateDocumentParent;

  @override
  Future<LibraryEntry> createDirectory(
    LibraryAccess access, {
    required String parentPath,
    required String name,
  }) async {
    lastCreateDirectoryParent = parentPath;
    return LibraryEntry(
      name: name,
      relativePath: parentPath.isEmpty ? name : '$parentPath/$name',
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
    lastCreateDocumentParent = parentPath;
    final isText = format == DocumentFormat.text;
    return LibraryEntry(
      name: name,
      relativePath: parentPath.isEmpty ? name : '$parentPath/$name',
      type: isText ? LibraryEntryType.textFile : LibraryEntryType.markdownFile,
    );
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
