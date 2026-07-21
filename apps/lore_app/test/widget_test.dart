import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_platform_adapters/lore_platform_adapters.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lore_app/app/lore_app.dart';
import 'package:lore_app/features/library/library_providers.dart';
import 'package:lore_app/features/workspace/document_pane.dart';
import 'package:lore_app/features/workspace/document_tabs.dart';
import 'package:lore_app/features/workspace/workspace_controller.dart';

void main() {
  setUp(() {
    // appPreferencesProvider 通过 SharedPreferences 加载；测试中必须 mock，
    // 否则 getInstance() 走平台 channel 会挂起，让 LoreApp 永久停在 loading。
    SharedPreferences.setMockInitialValues({});
  });

  test('activating a document tab clears structural selection', () async {
    const access = LibraryAccess(
      token: '/tmp/library',
      displayPath: '/tmp/library',
      isPending: false,
    );
    final metadata = LibraryMetadata(
      schemaVersion: 1,
      id: const LibraryId('11111111-1111-4111-8111-111111111111'),
      createdAt: DateTime.utc(2026, 7, 17),
      updatedAt: DateTime.utc(2026, 7, 17),
    );
    final repository = _FakeWorkspaceRepository();
    final controller = WorkspaceController(
      session: LibrarySession(access: access, metadata: metadata),
      service: LibraryWorkspaceService(
        treeRepository: repository,
        documentRepository: repository,
        sessionRepository: _MemoryWorkspaceSessionRepository(),
      ),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.openPath('第一章.md');
    controller.selectEntry(
      const LibraryEntry(
        name: '第一卷',
        relativePath: '长夜行/正文/第一卷',
        type: LibraryEntryType.directory,
        semanticKind: LibraryEntrySemanticKind.volume,
        semanticId: '33333333-3333-4333-8333-333333333333',
        novelId: '22222222-2222-4222-8222-222222222222',
      ),
    );

    await controller.activateTab(controller.tabs.single);

    expect(controller.selectedEntry, isNull);
    expect(controller.activePath, '第一章.md');
  });

  testWidgets('shows directory selection when no library is stored', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryAccessGatewayProvider.overrideWithValue(_FakeAccessGateway()),
          libraryRepositoryProvider.overrideWithValue(
            _FakeLibraryRepository(
              inspection: const LibraryInspectionNeedsInitialization(),
            ),
          ),
        ],
        child: const LoreApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('选择你的书库'), findsOneWidget);
    expect(find.text('选择书库目录'), findsOneWidget);
  });

  testWidgets('shows ready library entries', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const access = LibraryAccess(
      token: '/tmp/library',
      displayPath: '/tmp/library',
      isPending: false,
    );
    final metadata = LibraryMetadata(
      schemaVersion: 1,
      id: const LibraryId('11111111-1111-4111-8111-111111111111'),
      createdAt: DateTime.utc(2026, 7, 17),
      updatedAt: DateTime.utc(2026, 7, 17),
    );
    final workspaceRepository = _FakeWorkspaceRepository(
      entries: const [
        LibraryEntry(
          name: '第一章.md',
          relativePath: '第一章.md',
          type: LibraryEntryType.markdownFile,
        ),
      ],
    );
    final novelRepository = _FakeNovelRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryAccessGatewayProvider.overrideWithValue(
            _FakeAccessGateway(restoreAccess: access),
          ),
          libraryRepositoryProvider.overrideWithValue(
            _FakeLibraryRepository(
              inspection: LibraryInspectionReady(metadata),
            ),
          ),
          libraryTreeRepositoryProvider.overrideWithValue(workspaceRepository),
          documentRepositoryProvider.overrideWithValue(workspaceRepository),
          novelRepositoryProvider.overrideWithValue(novelRepository),
          contentTreeRepositoryProvider.overrideWithValue(novelRepository),
          workspaceSessionRepositoryProvider.overrideWithValue(
            _MemoryWorkspaceSessionRepository(),
          ),
        ],
        child: const LoreApp(),
      ),
    );
    await tester.pumpAndSettle();

    final sidebar = find.byKey(const ValueKey('library-sidebar'));
    final resizeHandle = find.byKey(
      const ValueKey('library-sidebar-resize-handle'),
    );
    final collapseButton = find.byKey(
      const ValueKey('library-sidebar-collapse'),
    );
    expect(tester.getSize(sidebar).width, 276);
    expect(
      find.descendant(of: sidebar, matching: collapseButton),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(AppBar), matching: collapseButton),
      findsNothing,
    );

    await tester.drag(resizeHandle, const Offset(80, 0));
    await tester.pump();
    expect(tester.getSize(sidebar).width, closeTo(356, 1));

    await tester.tap(find.byTooltip('收起侧栏'));
    await tester.pump();
    expect(sidebar, findsNothing);
    final expandButton = find.byKey(const ValueKey('library-sidebar-expand'));
    expect(expandButton, findsOneWidget);
    expect(
      tester.getTopLeft(expandButton).dy,
      closeTo(tester.getTopLeft(find.byType(DocumentTabs)).dy, 1),
    );

    await tester.tap(find.byTooltip('展开侧栏'));
    await tester.pumpAndSettle();
    expect(tester.getSize(sidebar).width, closeTo(356, 1));
    expect(expandButton, findsNothing);

    expect(find.text('/tmp/library'), findsOneWidget);
    expect(find.text('第一章.md'), findsOneWidget);
    expect(find.text('选择或新建文件开始写作'), findsOneWidget);
    expect(find.text('助手'), findsOneWidget);
    expect(find.text('大纲'), findsOneWidget);
    expect(find.text('信息'), findsOneWidget);

    await tester.tap(find.text('第一章.md'));
    await tester.pumpAndSettle();

    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('预览'), findsOneWidget);
    expect(find.text('已保存'), findsOneWidget);
    expect(find.text('4 字'), findsOneWidget);

    await tester.tap(find.text('信息'));
    await tester.pumpAndSettle();
    expect(find.text('4'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '# 新标题\n正文 内容');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('8 字'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);

    await tester.tap(find.text('大纲'));
    await tester.pumpAndSettle();
    expect(find.text('新标题'), findsOneWidget);

    tester.view.physicalSize = const Size(500, 900);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    final drawer = find.byType(Drawer);
    expect(drawer, findsOneWidget);
    await tester.tap(
      find.descendant(of: drawer, matching: find.text('第一章.md')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsNothing);
  });

  testWidgets(
    'dragging a desktop tab into the right content area creates split',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const access = LibraryAccess(
        token: '/tmp/library',
        displayPath: '/tmp/library',
        isPending: false,
      );
      final metadata = LibraryMetadata(
        schemaVersion: 1,
        id: const LibraryId('11111111-1111-4111-8111-111111111111'),
        createdAt: DateTime.utc(2026, 7, 17),
        updatedAt: DateTime.utc(2026, 7, 17),
      );
      final workspaceRepository = _FakeWorkspaceRepository(
        entries: const [
          LibraryEntry(
            name: '第一章.md',
            relativePath: '第一章.md',
            type: LibraryEntryType.markdownFile,
          ),
          LibraryEntry(
            name: '第二章.md',
            relativePath: '第二章.md',
            type: LibraryEntryType.markdownFile,
          ),
        ],
      );
      final sessionRepository = _MemoryWorkspaceSessionRepository()
        ..value = const WorkspaceSessionSnapshot(
          documents: [
            WorkspaceDocumentState(
              relativePath: '第一章.md',
              selectionBase: 0,
              selectionExtent: 0,
              scrollOffset: 0,
            ),
            WorkspaceDocumentState(
              relativePath: '第二章.md',
              selectionBase: 0,
              selectionExtent: 0,
              scrollOffset: 0,
            ),
          ],
          activePath: '第一章.md',
        );
      final novelRepository = _FakeNovelRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            libraryAccessGatewayProvider.overrideWithValue(
              _FakeAccessGateway(restoreAccess: access),
            ),
            libraryRepositoryProvider.overrideWithValue(
              _FakeLibraryRepository(
                inspection: LibraryInspectionReady(metadata),
              ),
            ),
            libraryTreeRepositoryProvider.overrideWithValue(
              workspaceRepository,
            ),
            documentRepositoryProvider.overrideWithValue(workspaceRepository),
            novelRepositoryProvider.overrideWithValue(novelRepository),
            contentTreeRepositoryProvider.overrideWithValue(novelRepository),
            workspaceSessionRepositoryProvider.overrideWithValue(
              sessionRepository,
            ),
          ],
          child: const LoreApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DocumentTabs), findsOneWidget);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byTooltip('第一章.md')),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump();

      final splitTarget = find.text('在右侧创建分屏');
      expect(splitTarget, findsNothing);

      final tabBarBounds = tester.getRect(find.byType(DocumentTabs));
      final leftContentPoint = Offset(
        tabBarBounds.left + tabBarBounds.width * 0.25,
        tabBarBounds.bottom + 120,
      );
      final rightContentPoint = Offset(
        tabBarBounds.left + tabBarBounds.width * 0.75,
        tabBarBounds.bottom + 120,
      );
      await gesture.moveTo(leftContentPoint);
      await tester.pump();
      expect(splitTarget, findsNothing);

      await gesture.moveTo(rightContentPoint);
      await tester.pump();
      expect(splitTarget, findsOneWidget);

      await gesture.moveTo(leftContentPoint);
      await tester.pump();
      expect(splitTarget, findsNothing);

      await gesture.moveTo(rightContentPoint);
      await tester.pump();
      expect(splitTarget, findsOneWidget);
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(splitTarget, findsNothing);
      expect(find.byType(DocumentTabs), findsOneWidget);

      final splitGesture = await tester.startGesture(
        tester.getCenter(find.byTooltip('第一章.md')),
        kind: PointerDeviceKind.mouse,
      );
      await splitGesture.moveBy(const Offset(24, 0));
      await tester.pump();
      await splitGesture.moveTo(rightContentPoint);
      await tester.pump();
      expect(splitTarget, findsOneWidget);
      await splitGesture.up();
      await tester.pumpAndSettle();

      expect(find.byType(DocumentTabs), findsNWidgets(2));

      tester.view.physicalSize = const Size(565, 900);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(DocumentTabs), findsOneWidget);

      tester.view.physicalSize = const Size(1400, 900);
      await tester.pumpAndSettle();
      expect(find.byType(DocumentTabs), findsNWidgets(2));

      final secondGesture = await tester.startGesture(
        tester.getCenter(find.byTooltip('第二章.md')),
        kind: PointerDeviceKind.mouse,
      );
      await secondGesture.moveBy(const Offset(24, 0));
      await tester.pump();
      await secondGesture.moveTo(tester.getCenter(find.byType(DocumentPane)));
      await tester.pump();
      await secondGesture.up();
      await tester.pump(const Duration(milliseconds: 600));

      final groups = sessionRepository.value!.editorGroups;
      expect(
        groups
            .singleWhere((group) => group.id == WorkspaceEditorGroupId.primary)
            .tabPaths,
        isEmpty,
      );
      expect(
        groups
            .singleWhere(
              (group) => group.id == WorkspaceEditorGroupId.secondary,
            )
            .tabPaths,
        ['第一章.md', '第二章.md'],
      );
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('creates a novel from the workspace toolbar', (tester) async {
    const access = LibraryAccess(
      token: '/tmp/library',
      displayPath: '/tmp/library',
      isPending: false,
    );
    final metadata = LibraryMetadata(
      schemaVersion: 1,
      id: const LibraryId('11111111-1111-4111-8111-111111111111'),
      createdAt: DateTime.utc(2026, 7, 17),
      updatedAt: DateTime.utc(2026, 7, 17),
    );
    final workspaceRepository = _FakeWorkspaceRepository();
    final novelRepository = _FakeNovelRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryAccessGatewayProvider.overrideWithValue(
            _FakeAccessGateway(restoreAccess: access),
          ),
          libraryRepositoryProvider.overrideWithValue(
            _FakeLibraryRepository(
              inspection: LibraryInspectionReady(metadata),
            ),
          ),
          libraryTreeRepositoryProvider.overrideWithValue(workspaceRepository),
          documentRepositoryProvider.overrideWithValue(workspaceRepository),
          novelRepositoryProvider.overrideWithValue(novelRepository),
          contentTreeRepositoryProvider.overrideWithValue(novelRepository),
          workspaceSessionRepositoryProvider.overrideWithValue(
            _MemoryWorkspaceSessionRepository(),
          ),
        ],
        child: const LoreApp(),
      ),
    );
    await tester.pumpAndSettle();

    final dividerCount = tester
        .widgetList<Divider>(find.byType(Divider))
        .length;
    await tester.tap(find.byTooltip('新建'));
    await tester.pumpAndSettle();
    final newButton = find.ancestor(
      of: find.byIcon(Icons.add_rounded),
      matching: find.byType(IconButton),
    );
    final menuItems = tester
        .widgetList<MenuItemButton>(find.byType(MenuItemButton))
        .toList();
    expect(menuItems, hasLength(4));
    expect(menuItems.every((item) => item.leadingIcon == null), isTrue);
    expect(
      tester.getTopLeft(find.byType(MenuItemButton).first).dx,
      closeTo(tester.getTopLeft(newButton).dx, 1),
    );
    expect(
      tester.getTopLeft(find.byType(MenuItemButton).first).dy,
      greaterThan(tester.getBottomLeft(newButton).dy),
    );
    expect(
      tester.widgetList<Divider>(find.byType(Divider)),
      hasLength(dividerCount),
    );
    await tester.tap(find.text('新建小说'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '长夜行');
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(novelRepository.createdTitles, ['长夜行']);
    expect(find.text('长夜行'), findsOneWidget);
  });

  testWidgets('confirms before initializing an ordinary directory', (
    tester,
  ) async {
    const pendingAccess = LibraryAccess(
      token: '/tmp/new-library',
      displayPath: '/tmp/new-library',
      isPending: true,
    );
    final gateway = _FakeAccessGateway(selectAccess: pendingAccess);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryAccessGatewayProvider.overrideWithValue(gateway),
          libraryRepositoryProvider.overrideWithValue(
            _FakeLibraryRepository(
              inspection: const LibraryInspectionNeedsInitialization(),
            ),
          ),
        ],
        child: const LoreApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('选择书库目录'));
    await tester.pumpAndSettle();

    expect(find.text('初始化书库？'), findsOneWidget);
    expect(find.textContaining('不会修改现有文件'), findsOneWidget);

    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();

    expect(find.text('选择你的书库'), findsOneWidget);
    expect(gateway.discardCount, 1);
  });

  testWidgets('shows unsupported state on Android gateway', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryAccessGatewayProvider.overrideWithValue(
            const UnsupportedLibraryAccessGateway(),
          ),
          libraryRepositoryProvider.overrideWithValue(
            _FakeLibraryRepository(
              inspection: const LibraryInspectionNeedsInitialization(),
            ),
          ),
        ],
        child: const LoreApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('当前平台暂未支持'), findsOneWidget);
    expect(find.text('Android 书库支持将在后续版本提供。'), findsOneWidget);
  });
}

final class _FakeAccessGateway implements LibraryAccessGateway {
  _FakeAccessGateway({this.restoreAccess, this.selectAccess});

  final LibraryAccess? restoreAccess;
  final LibraryAccess? selectAccess;
  int discardCount = 0;

  @override
  Future<void> clear() async {}

  @override
  Future<void> commit() async {}

  @override
  Future<void> discard() async {
    discardCount += 1;
  }

  @override
  Future<LibraryAccess?> restore() async => restoreAccess;

  @override
  Future<LibraryAccess?> select() async => selectAccess;
}

final class _FakeLibraryRepository implements LibraryRepository {
  _FakeLibraryRepository({required this.inspection});

  final LibraryInspection inspection;

  @override
  Future<LibraryMetadata> initialize(LibraryAccess access) async {
    throw UnimplementedError();
  }

  @override
  Future<LibraryInspection> inspect(LibraryAccess access) async => inspection;

  @override
  Future<List<LibraryEntry>> listChildren(
    LibraryAccess access, {
    String relativePath = '',
  }) async {
    return const [];
  }
}

final class _FakeWorkspaceRepository
    implements LibraryTreeRepository, DocumentRepository {
  _FakeWorkspaceRepository({this.entries = const []});

  final List<LibraryEntry> entries;

  @override
  Future<LibraryEntry> createDirectory(
    LibraryAccess access, {
    required String parentPath,
    required String name,
  }) async {
    return LibraryEntry(
      name: name,
      relativePath: name,
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
    return LibraryEntry(
      name: '$name$extension',
      relativePath: '$name$extension',
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
    return entries;
  }

  @override
  Future<DocumentSnapshot> readDocument(
    LibraryAccess access,
    DocumentRef ref,
  ) async {
    return DocumentSnapshot(
      ref: ref,
      text: '# 第一章',
      encoding: TextEncoding.utf8,
      lineEnding: LineEnding.lf,
      revision: const DocumentRevision('revision-1'),
    );
  }

  @override
  Future<LibraryEntry> renameEntry(
    LibraryAccess access, {
    required String relativePath,
    required String newName,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<DocumentSaveResult> saveDocument(
    LibraryAccess access, {
    required DocumentSnapshot original,
    required String text,
  }) async {
    return DocumentSaveSuccess(
      DocumentSnapshot(
        ref: original.ref,
        text: text,
        encoding: original.encoding,
        lineEnding: original.lineEnding,
        revision: const DocumentRevision('revision-2'),
      ),
    );
  }

  @override
  Stream<DocumentChange> watchDocuments(LibraryAccess access) {
    return const Stream.empty();
  }

  @override
  Future<DeletionResult> deleteEntry(
    LibraryAccess access, {
    required String relativePath,
  }) {
    throw UnimplementedError();
  }
}

final class _MemoryWorkspaceSessionRepository
    implements WorkspaceSessionRepository {
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

final class _FakeNovelRepository
    implements NovelRepository, ContentTreeRepository {
  final createdTitles = <String>[];
  final snapshots = <NovelSnapshot>[];

  @override
  Future<List<NovelSnapshot>> listNovels(LibraryAccess access) async =>
      snapshots;

  @override
  Future<NovelSnapshot> loadNovel(
    LibraryAccess access, {
    required NovelId novelId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<NovelStructureMutation> createNovel(
    LibraryAccess access, {
    required String title,
    ChapterFormat chapterFormat = ChapterFormat.markdown,
  }) async {
    createdTitles.add(title);
    final now = DateTime.utc(2026, 7, 17);
    final snapshot = NovelSnapshot(
      rootPath: title,
      metadata: NovelMetadata(
        schemaVersion: 1,
        id: const NovelId('22222222-2222-4222-8222-222222222222'),
        title: title,
        description: '',
        coverPath: null,
        body: const NovelBody(
          id: ContentId('33333333-3333-4333-8333-333333333333'),
          relativePath: '正文',
        ),
        chapterFormat: ChapterFormat.markdown,
        numberingMode: NumberingMode.continuous,
        createdAt: now,
        updatedAt: now,
      ),
      contentTree: const ContentTree(
        schemaVersion: 1,
        novelId: NovelId('22222222-2222-4222-8222-222222222222'),
        revision: 0,
        nodes: [],
      ),
    );
    snapshots.add(snapshot);
    return NovelStructureMutation(
      snapshot: snapshot,
      entry: LibraryEntry(
        name: title,
        relativePath: title,
        type: LibraryEntryType.directory,
        semanticKind: LibraryEntrySemanticKind.novel,
        semanticId: snapshot.metadata.id.value,
        novelId: snapshot.metadata.id.value,
      ),
    );
  }

  @override
  Future<NovelStructureMutation> registerExistingNovel(
    LibraryAccess access, {
    required String relativePath,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<NovelStructureMutation> importNovel(
    LibraryAccess access, {
    required String title,
    required List<ParsedSection> sections,
    ChapterFormat chapterFormat = ChapterFormat.text,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<NovelStructureMutation> renameNovel(
    LibraryAccess access, {
    required NovelId novelId,
    required String newName,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<NovelStructureMutation> renameBody(
    LibraryAccess access, {
    required NovelId novelId,
    required String newName,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<NovelStructureMutation> createVolume(
    LibraryAccess access, {
    required NovelId novelId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<NovelStructureMutation> createChapter(
    LibraryAccess access, {
    required NovelId novelId,
    ContentId? volumeId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<NovelStructureMutation> moveChapter(
    LibraryAccess access, {
    required NovelId novelId,
    required ContentId chapterId,
    ContentId? volumeId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<NovelStructureMutation> renameNode(
    LibraryAccess access, {
    required NovelId novelId,
    required ContentId nodeId,
    required String newName,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<NovelReconciliationResult> reconcile(
    LibraryAccess access, {
    required NovelId novelId,
  }) async {
    return NovelReconciliationResult(
      snapshot: snapshots.firstWhere(
        (snapshot) => snapshot.metadata.id == novelId,
      ),
    );
  }

  @override
  Future<NovelStructureMutation> reorderNode(
    LibraryAccess access, {
    required NovelId novelId,
    required ContentId nodeId,
    required int newIndex,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<DeletionResult> deleteNode(
    LibraryAccess access, {
    required NovelId novelId,
    required ContentId nodeId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<DeletionResult> deleteNovel(
    LibraryAccess access, {
    required NovelId novelId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<NovelStructureMutation> updateChapterCharacterCounts(
    LibraryAccess access, {
    required NovelId novelId,
    required Map<ContentId, int> characterCounts,
  }) {
    throw UnimplementedError();
  }
}
