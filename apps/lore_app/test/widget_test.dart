import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_platform_adapters/lore_platform_adapters.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lore_app/app/lore_app.dart';
import 'package:lore_app/features/library/library_providers.dart';
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
    expect(find.text('本文 4 字'), findsOneWidget);

    await tester.tap(find.text('信息'));
    await tester.pumpAndSettle();
    expect(find.text('4'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '# 新标题\n正文 内容');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('本文 8 字'), findsOneWidget);
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
    final menuItems = tester
        .widgetList<MenuItemButton>(find.byType(MenuItemButton))
        .toList();
    expect(menuItems, hasLength(4));
    expect(menuItems.every((item) => item.leadingIcon == null), isTrue);
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
}
