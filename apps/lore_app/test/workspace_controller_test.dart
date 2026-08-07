import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_app/features/preferences/preferences_providers.dart';
import 'package:lore_app/features/workspace/document_pane.dart';
import 'package:lore_app/features/workspace/chapter_title_bar.dart';
import 'package:lore_app/features/workspace/novel_search_controller.dart';
import 'package:lore_app/features/workspace/workspace_controller.dart';
import 'package:lore_app/features/workspace/workspace_novel_store.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_editor/lore_editor.dart';
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

  test('history and tabs stores initialize without a late-final cycle', () {
    // 回归守护：_tabsStore 与 _historyStore 互相注入回调，曾因注入
    // _tabsStore.reloadDocumentFromDisk 的 tear-off 在初始化期强制求值尚未完成的
    // _tabsStore 而栈溢出。访问两侧 getter 触发 late final 初始化，确认无递归。
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
    addTearDown(controller.dispose);

    expect(controller.tabs, isEmpty); // 触发 _tabsStore
    expect(controller.diffTarget, isNull); // 触发 _historyStore
  });

  test('new novel search query clears stale results immediately', () async {
    final snapshot = _chapterNovelSnapshot();
    final repository = _MemoryWorkspaceRepository()..diskText = '第1章\n正文段';
    final controller = WorkspaceController(
      session: session,
      service: LibraryWorkspaceService(
        treeRepository: repository,
        documentRepository: repository,
        sessionRepository: _MemorySessionRepository(),
      ),
      novelStructureService: NovelStructureService(
        novelRepository: _FakeNovelRepository(snapshot),
        contentTreeRepository: _FakeContentTreeRepository(snapshot),
      ),
    );
    final search = NovelSearchController(
      workspace: controller,
      session: session,
    );
    addTearDown(repository.dispose);
    addTearDown(search.dispose);
    addTearDown(controller.dispose);

    await controller.initialize();
    await controller.openPath('我的小说/正文/第1章.txt');
    search.setPattern('正文');
    await search.runSearch();
    expect(search.results, isNotEmpty);

    search.setPattern('新查询');
    expect(search.results, isEmpty);
    expect(search.searching, isTrue);
  });

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

  testWidgets('markdown chapter title splits and recomposes with # heading', (
    tester,
  ) async {
    final repository = _MemoryWorkspaceRepository()..diskText = '# 第1章\n正文段';
    final controller = WorkspaceController(
      session: session,
      service: LibraryWorkspaceService(
        treeRepository: repository,
        documentRepository: repository,
        sessionRepository: _MemorySessionRepository(),
      ),
    );
    addTearDown(repository.dispose);
    addTearDown(controller.dispose);

    await controller.initialize();
    await controller.openPath('第1章.md');
    final document = controller.activeDocument!;
    // 首行 `# 第1章` 被识别为标题：编辑器只持有正文，副标题独立存储。
    expect(document.isMarkdown, isTrue);
    expect(document.chapterNumber, 1);
    expect(document.chapterTitleSubtitle, '');
    expect(document.editorController.text, '正文段');

    controller.updateChapterTitleSubtitle(document, '甜蜜的家');
    await tester.pump(const Duration(milliseconds: 900)); // 自动保存(800ms)
    await tester.pump(
      const Duration(milliseconds: 700),
    ); // 标题同步(1000ms) + 会话保存(1300ms)
    await tester.pump();

    // 落盘首行仍以 `# ` 写作 Markdown H1。
    expect(repository.savedTexts.last, '# 第1章 甜蜜的家\n正文段');
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

  test('chapterNodeForPath resolves registered chapters only', () {
    final store = WorkspaceNovelStore(session: session);
    store.replace(_chapterNovelSnapshot());
    final match = store.chapterNodeForPath('我的小说/正文/第1章.txt');
    expect(match, isNotNull);
    expect(match!.node.id, ContentId('chapter-1'));
    expect(match.novel.metadata.id, NovelId('novel-1'));
    // 卷目录、库外散文件均不匹配。
    expect(store.chapterNodeForPath('我的小说/正文'), isNull);
    expect(store.chapterNodeForPath('散文件.txt'), isNull);
  });

  test('character count updates preserve the semantic entry index', () {
    final store = WorkspaceNovelStore(session: session);
    store.replace(_chapterNovelSnapshot());
    final entry = store.semanticEntryIndex['我的小说/正文/第1章.txt'];

    store.replace(
      _chapterNovelSnapshot(characterCount: 128),
      semanticStructureChanged: false,
    );

    expect(
      store
          .novelById(const NovelId('novel-1'))!
          .contentTree
          .nodes
          .single
          .characterCount,
      128,
    );
    expect(
      identical(store.semanticEntryIndex['我的小说/正文/第1章.txt'], entry),
      isTrue,
    );
  });

  testWidgets('subtitle change syncs the chapter filename', (tester) async {
    final snapshot = _chapterNovelSnapshot();
    final novelRepo = _FakeNovelRepository(snapshot);
    final treeRepo = _FakeContentTreeRepository(snapshot);
    final repository = _MemoryWorkspaceRepository()..diskText = '第1章\n正文段';
    final controller = WorkspaceController(
      session: session,
      service: LibraryWorkspaceService(
        treeRepository: repository,
        documentRepository: repository,
        sessionRepository: _MemorySessionRepository(),
      ),
      novelStructureService: NovelStructureService(
        novelRepository: novelRepo,
        contentTreeRepository: treeRepo,
      ),
    );
    addTearDown(repository.dispose);
    addTearDown(controller.dispose);

    await controller.initialize();
    await controller.openPath('我的小说/正文/第1章.txt');
    final document = controller.activeDocument!;
    expect(document.chapterNumber, 1);

    controller.updateChapterTitleSubtitle(document, '甜蜜的家');
    // 自动保存(800ms) 先把含新副标题的首行落盘，标题同步(1000ms) 随后重命名；
    // 再多 pump 一段以触发重命名安排的会话保存(500ms) 定时器，避免遗留。
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();

    expect(treeRepo.lastRenameNewName, '第1章 甜蜜的家');
    expect(treeRepo.lastRenameNodeId, ContentId('chapter-1'));
    // 开放文档路径经 pathChanges 重写到新文件名；Tab 与目录树随之跟随。
    expect(document.relativePath, '我的小说/正文/第1章 甜蜜的家.txt');
    expect(controller.activePath, '我的小说/正文/第1章 甜蜜的家.txt');
  });

  testWidgets('closing the tab cancels the pending title sync', (tester) async {
    final snapshot = _chapterNovelSnapshot();
    final novelRepo = _FakeNovelRepository(snapshot);
    final treeRepo = _FakeContentTreeRepository(snapshot);
    final repository = _MemoryWorkspaceRepository()..diskText = '第1章\n正文段';
    final controller = WorkspaceController(
      session: session,
      service: LibraryWorkspaceService(
        treeRepository: repository,
        documentRepository: repository,
        sessionRepository: _MemorySessionRepository(),
      ),
      novelStructureService: NovelStructureService(
        novelRepository: novelRepo,
        contentTreeRepository: treeRepo,
      ),
    );
    addTearDown(repository.dispose);
    addTearDown(controller.dispose);

    await controller.initialize();
    await controller.openPath('我的小说/正文/第1章.txt');
    final document = controller.activeDocument!;
    controller.updateChapterTitleSubtitle(document, '甜蜜的家');
    // 在标题同步(1000ms) 触发前关闭标签：dispose 取消 titleSyncTimer。
    expect(await controller.closeTab(document), isTrue);
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump();

    expect(treeRepo.lastRenameNewName, isNull);
  });

  testWidgets(
    'refreshes an open chapter locked prefix after rename changes its number',
    (tester) async {
      final snapshot = _chapterNovelSnapshot();
      final novelRepo = _FakeNovelRepository(snapshot);
      final treeRepo = _FakeContentTreeRepository(snapshot);
      final repository = _MemoryWorkspaceRepository()..diskText = '第1章\n正文段';
      final controller = WorkspaceController(
        session: session,
        service: LibraryWorkspaceService(
          treeRepository: repository,
          documentRepository: repository,
          sessionRepository: _MemorySessionRepository(),
        ),
        novelStructureService: NovelStructureService(
          novelRepository: novelRepo,
          contentTreeRepository: treeRepo,
        ),
      );
      addTearDown(repository.dispose);
      addTearDown(controller.dispose);

      await controller.initialize();
      await controller.openPath('我的小说/正文/第1章.txt');
      expect(controller.activeDocument!.chapterNumber, 1);

      // 重命名「第1章」→「第2章」：文件名号变了，已打开标签的锁定前缀应即时刷新
      // （不依赖文件 watch 回流）。
      await controller.renameContentNode(
        snapshot.metadata.id,
        ContentId('chapter-1'),
        '第2章',
      );
      // 结构变更会安排一次会话保存（500ms）；pump 过它，避免遗留 pending timer。
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();

      final active = controller.activeDocument!;
      expect(active.chapterNumber, 2);
      expect(active.relativePath, '我的小说/正文/第2章.txt');
    },
  );

  testWidgets('refreshes a chapter number in the unfocused editor group', (
    tester,
  ) async {
    final snapshot = _chapterNovelSnapshot();
    final novelRepo = _FakeNovelRepository(snapshot);
    final treeRepo = _FakeContentTreeRepository(snapshot);
    final repository = _MemoryWorkspaceRepository()..diskText = '第1章\n正文段';
    final controller = WorkspaceController(
      session: session,
      service: LibraryWorkspaceService(
        treeRepository: repository,
        documentRepository: repository,
        sessionRepository: _MemorySessionRepository(),
      ),
      novelStructureService: NovelStructureService(
        novelRepository: novelRepo,
        contentTreeRepository: treeRepo,
      ),
    );
    addTearDown(repository.dispose);
    addTearDown(controller.dispose);

    await controller.initialize();
    await controller.openPath('我的小说/正文/第1章.txt');
    final document = controller.activeDocument!;
    controller.splitRight(document);
    controller.focusGroup(WorkspaceEditorGroupId.primary);

    await controller.renameContentNode(
      snapshot.metadata.id,
      ContentId('chapter-1'),
      '第2章',
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(controller.focusedGroupId, WorkspaceEditorGroupId.primary);
    expect(document.chapterNumber, 2);
    expect(document.relativePath, '我的小说/正文/第2章.txt');
  });

  testWidgets(
    'saved first line and filename agree for a leading-dot subtitle',
    (tester) async {
      final snapshot = _chapterNovelSnapshot();
      final novelRepo = _FakeNovelRepository(snapshot);
      final treeRepo = _FakeContentTreeRepository(snapshot);
      final repository = _MemoryWorkspaceRepository()..diskText = '第1章\n正文段';
      final controller = WorkspaceController(
        session: session,
        service: LibraryWorkspaceService(
          treeRepository: repository,
          documentRepository: repository,
          sessionRepository: _MemorySessionRepository(),
        ),
        novelStructureService: NovelStructureService(
          novelRepository: novelRepo,
          contentTreeRepository: treeRepo,
        ),
      );
      addTearDown(repository.dispose);
      addTearDown(controller.dispose);

      await controller.initialize();
      await controller.openPath('我的小说/正文/第1章.txt');
      final document = controller.activeDocument!;
      // 前导点：输入过滤器本会拦，这里直接置入以验证保存与重命名都净化掉它，
      // 使落盘首行与文件名一致（不出现「每次编辑都重命名」的漂移）。
      controller.updateChapterTitleSubtitle(document, '.序');

      await tester.pump(const Duration(milliseconds: 900)); // 自动保存(800ms)
      await tester.pump();
      expect(repository.savedTexts.last, '第1章 序\n正文段');

      await tester.pump(const Duration(milliseconds: 900)); // 标题同步(1000ms)
      await tester.pump();
      expect(treeRepo.lastRenameNewName, '第1章 序');
    },
  );

  testWidgets('self-rename watch back-flow keeps the open doc clean', (
    tester,
  ) async {
    // 重命名会触发存储层文件监听回流（delete 旧 + create 新）。开放文档不应因此
    // 进入假冲突或被重载：_inspectExternalChange 在 revision 一致时早返回。
    final snapshot = _chapterNovelSnapshot();
    final novelRepo = _FakeNovelRepository(snapshot);
    final repository = _MemoryWorkspaceRepository()..diskText = '第1章\n正文段';
    // 把重命名的 watch 事件灌入文档仓储的 changes 流，模拟真实存储层回流。
    final treeRepo = _FakeContentTreeRepository(
      snapshot,
      watchSink: repository.changes,
    );
    final controller = WorkspaceController(
      session: session,
      service: LibraryWorkspaceService(
        treeRepository: repository,
        documentRepository: repository,
        sessionRepository: _MemorySessionRepository(),
      ),
      novelStructureService: NovelStructureService(
        novelRepository: novelRepo,
        contentTreeRepository: treeRepo,
      ),
    );
    addTearDown(repository.dispose);
    addTearDown(controller.dispose);

    await controller.initialize();
    await controller.openPath('我的小说/正文/第1章.txt');
    final document = controller.activeDocument!;
    controller.updateChapterTitleSubtitle(document, '甜蜜的家');
    // 跨过 自动保存(800) + 标题同步(1000) + 外部变更复检(180) + reconcile(180) + 会话保存(500)。
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump();

    expect(treeRepo.lastRenameNewName, '第1章 甜蜜的家');
    expect(document.relativePath, '我的小说/正文/第1章 甜蜜的家.txt');
    // 关键：回流未造成假冲突，也未重载——状态干净、正文原样。
    expect(document.saveStatus, DocumentSaveStatus.clean);
    expect(document.editorController.text, '正文段');
  });

  testWidgets('editor does not remount on a path-only rename', (tester) async {
    // 副标题→文件名重命名只改 relativePath（文档实例不变）。编辑器若按路径作 key
    // 会整体重挂载、autofocus 抢走正文首段焦点。这里断言重命名前后编辑器元素
    // 是同一个（未重挂载），副标题字段也保持焦点。
    final repository = _MemoryWorkspaceRepository()..diskText = '第1章\n正文段';
    final controller = WorkspaceController(
      session: session,
      service: LibraryWorkspaceService(
        treeRepository: repository,
        documentRepository: repository,
        sessionRepository: _MemorySessionRepository(),
      ),
    );
    addTearDown(repository.dispose);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.openPath('第1章.txt');
    final document = controller.activeDocument!;
    expect(document.chapterNumber, 1);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appPreferencesRepositoryProvider.overrideWith(
            (ref) => _DefaultsPrefsRepository(),
          ),
        ],
        child: MaterialApp(
          home: Material(
            child: DocumentPane(
              controller: controller,
              document: document,
              session: session,
              onReloadConflict: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));

    final editorBefore = tester.element(find.byType(LoreLargeTextEditor));
    // 聚焦副标题字段（标题栏的 TextField 排在编辑器正文块之前）。
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    final subtitleNode = FocusManager.instance.primaryFocus;

    // 模拟重命名：仅改文档路径（同实例），触发 DocumentPane 重建。
    document.snapshot = DocumentSnapshot(
      ref: document.snapshot.ref.copyWith(relativePath: '第1章 甜蜜的家.txt'),
      text: document.snapshot.text,
      encoding: document.snapshot.encoding,
      lineEnding: document.snapshot.lineEnding,
      revision: document.snapshot.revision,
    );
    document.notifyChanged();
    await tester.pump();

    final editorAfter = tester.element(find.byType(LoreLargeTextEditor));
    expect(identical(editorBefore, editorAfter), isTrue);
    // 副标题仍持焦点（未被编辑器 autofocus 抢走）。
    expect(FocusManager.instance.primaryFocus, same(subtitleNode));
    // 打开文档时安排的会话保存定时器在这里落地，避免 teardown 报遗留。
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets(
    'chapter title is mounted inside the editor so it scrolls with the body',
    (tester) async {
      // .txt 章节走 LoreLargeTextController：标题应作为编辑器滚动视口的 header
      // （编辑器后代）注入，而非外层 Column 的固定兄弟——否则标题不会随正文滚动。
      final repository = _MemoryWorkspaceRepository()..diskText = '第1章\n正文段';
      final controller = WorkspaceController(
        session: session,
        service: LibraryWorkspaceService(
          treeRepository: repository,
          documentRepository: repository,
          sessionRepository: _MemorySessionRepository(),
        ),
      );
      addTearDown(repository.dispose);
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.openPath('第1章.txt');
      final document = controller.activeDocument!;
      expect(document.chapterNumber, 1);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appPreferencesRepositoryProvider.overrideWith(
              (ref) => _DefaultsPrefsRepository(),
            ),
          ],
          child: MaterialApp(
            home: Material(
              child: DocumentPane(
                controller: controller,
                document: document,
                session: session,
                onReloadConflict: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));

      // 标题渲染为编辑器的后代（滚动视口 header），而非与编辑器并列的固定节点。
      expect(
        find.descendant(
          of: find.byType(LoreLargeTextEditor),
          matching: find.byType(ChapterTitleBar),
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

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

  test(
    'revealEntry throws platformUnsupported without a reveal gateway',
    () async {
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
      addTearDown(controller.dispose);
      await expectLater(
        controller.revealEntry('foo'),
        throwsA(
          isA<LibraryOperationException>().having(
            (error) => error.failure.code,
            'code',
            LibraryFailureCode.platformUnsupported,
          ),
        ),
      );
    },
  );

  testWidgets('saving a chapter writes its character count back', (
    tester,
  ) async {
    final snapshot = _chapterNovelSnapshot();
    final novelRepo = _FakeNovelRepository(snapshot);
    final treeRepo = _FakeContentTreeRepository(snapshot);
    final repository = _MemoryWorkspaceRepository()..diskText = '第1章\n正文段';
    final controller = WorkspaceController(
      session: session,
      service: LibraryWorkspaceService(
        treeRepository: repository,
        documentRepository: repository,
        sessionRepository: _MemorySessionRepository(),
      ),
      novelStructureService: NovelStructureService(
        novelRepository: novelRepo,
        contentTreeRepository: treeRepo,
      ),
    );
    addTearDown(repository.dispose);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.openPath('我的小说/正文/第1章.txt');
    // 改正文让文档变脏，自动保存 800ms 防抖触发 _performSave → onChapterSaved →
    // updateChapterCharacterCounts，字数写回 content.json。
    controller.activeDocument!.editorController.text = '正文段改';
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(treeRepo.lastCharacterCounts, isNotNull);
    expect(treeRepo.lastCharacterCounts![ContentId('chapter-1')], isNotNull);
  });

  testWidgets('clearing all highlights removes the persisted record', (
    tester,
  ) async {
    // 回归:右键菜单点"无颜色"取消全部高亮后,磁盘记录必须被清除;否则重启后
    // _loadHighlightsIntoDocument 会从 highlights.json 读回旧高亮,颜色"复活"。
    final snapshot = _chapterNovelSnapshot();
    final novelRepo = _FakeNovelRepository(snapshot);
    final treeRepo = _FakeContentTreeRepository(snapshot);
    final repository = _MemoryWorkspaceRepository()..diskText = '第1章\n正文段';
    final controller = WorkspaceController(
      session: session,
      service: LibraryWorkspaceService(
        treeRepository: repository,
        documentRepository: repository,
        sessionRepository: _MemorySessionRepository(),
        highlightRepository: repository,
      ),
      novelStructureService: NovelStructureService(
        novelRepository: novelRepo,
        contentTreeRepository: treeRepo,
      ),
    );
    addTearDown(repository.dispose);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.openPath('我的小说/正文/第1章.txt');
    final document = controller.activeDocument!;
    final largeController =
        document.editorController as LoreLargeTextController;
    final bodyLength = largeController.text.length;

    // 上色并保存:磁盘落一条高亮记录。
    largeController.addHighlight(0, bodyLength, 0xFFFFD54F);
    expect(await controller.saveDocument(document), isTrue);
    expect(
      repository.highlightsByDocument['我的小说/正文/第1章.txt']?.highlights,
      hasLength(1),
    );

    // 取消全部(等价右键菜单点"无颜色"色块)并保存。
    largeController.removeHighlightsIntersecting(0, bodyLength);
    expect(largeController.highlights, isEmpty);
    expect(await controller.saveDocument(document), isTrue);

    // 修复后:该文档的磁盘高亮记录被清除,不再残留可"复活"的旧高亮。
    expect(
      repository.highlightsByDocument.containsKey('我的小说/正文/第1章.txt'),
      isFalse,
    );
    // 让自动保存链路安排的 session/statistics 定时器自然落地,避免遗留 pending timer。
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
  });

  testWidgets('reconcile losing all highlights clears the stale record', (
    tester,
  ) async {
    // 文档被外部修改后,若 reconcile 把全部旧高亮判为 lost,磁盘仍留旧记录;
    // 修复前 _loadHighlightsIntoDocument 的 isNotEmpty 守卫阻止清理,下次打开
    // 还会反复 reconcile 同一批陈旧高亮(内存与磁盘间"复活")。修复后无条件
    // _persistHighlights:located 为空 → deleteHighlights 清盘。
    final snapshot = _chapterNovelSnapshot();
    final novelRepo = _FakeNovelRepository(snapshot);
    final treeRepo = _FakeContentTreeRepository(snapshot);
    final repository = _MemoryWorkspaceRepository();
    // 新磁盘内容与旧高亮锚点毫无关联 → reconcile 必然全部 lost。
    repository.diskText = '全新的正文内容';
    repository.revision = 2;
    // 预置旧高亮记录:基于旧 revision、旧段落指纹;锚点 '旧段' 在新文本中不存在。
    repository.highlightsByDocument['我的小说/正文/第1章.txt'] = HighlightCollection(
      documentRevision: 'revision-1',
      paragraphDigests: computeParagraphProfile('旧段落正文').digests,
      highlights: const [
        Highlight(
          id: 'h0',
          start: 0,
          end: 2,
          colorArgb: 0xFFFFD54F,
          anchorText: '旧段',
        ),
      ],
    );
    final controller = WorkspaceController(
      session: session,
      service: LibraryWorkspaceService(
        treeRepository: repository,
        documentRepository: repository,
        sessionRepository: _MemorySessionRepository(),
        highlightRepository: repository,
      ),
      novelStructureService: NovelStructureService(
        novelRepository: novelRepo,
        contentTreeRepository: treeRepo,
      ),
    );
    addTearDown(repository.dispose);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.openPath('我的小说/正文/第1章.txt');

    // reconcile 全部 lost → 内存高亮为空,磁盘陈旧记录被清除。
    final largeController =
        controller.activeDocument!.editorController as LoreLargeTextController;
    expect(largeController.highlights, isEmpty);
    expect(
      repository.highlightsByDocument.containsKey('我的小说/正文/第1章.txt'),
      isFalse,
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
  });

  // ---- Tab 批量关闭（右键菜单「关闭其他/关闭右侧/关闭全部」的底层支持）----

  testWidgets('closeOthers closes every tab except the kept one', (
    tester,
  ) async {
    final repository = _MemoryWorkspaceRepository();
    final controller = buildController(repository);
    addTearDown(repository.dispose);
    await controller.initialize();
    await controller.openPath('a.txt');
    await controller.openPath('b.txt');
    await controller.openPath('c.txt');
    final keep = controller.tabs[1]; // b

    final stuck = await controller.closeOthers(keep);

    expect(stuck, isEmpty);
    expect(controller.tabs, hasLength(1));
    expect(controller.tabs.single.relativePath, 'b.txt');
    controller.dispose();
  });

  testWidgets('closeTabsToRight closes only tabs right of the anchor', (
    tester,
  ) async {
    final repository = _MemoryWorkspaceRepository();
    final controller = buildController(repository);
    addTearDown(repository.dispose);
    await controller.initialize();
    await controller.openPath('a.txt');
    await controller.openPath('b.txt');
    await controller.openPath('c.txt');
    await controller.openPath('d.txt');
    final anchor = controller.tabs[1]; // b

    final stuck = await controller.closeTabsToRight(anchor);

    expect(stuck, isEmpty);
    expect(controller.tabs.map((t) => t.relativePath).toList(), [
      'a.txt',
      'b.txt',
    ]);
    controller.dispose();
  });

  testWidgets('closeAllTabs closes every tab', (tester) async {
    final repository = _MemoryWorkspaceRepository();
    final controller = buildController(repository);
    addTearDown(repository.dispose);
    await controller.initialize();
    await controller.openPath('a.txt');
    await controller.openPath('b.txt');

    final stuck = await controller.closeAllTabs();

    expect(stuck, isEmpty);
    expect(controller.tabs, isEmpty);
    expect(controller.activePath, isNull);
    controller.dispose();
  });

  testWidgets('closeOthers skips conflict tabs and reports them as stuck', (
    tester,
  ) async {
    // 让 b 进入冲突态：本地改动 + 推进磁盘 revision，触发自动保存冲突——
    // 与「external modification enters conflict」同一路径，稳定可复现。
    final repository = _MemoryWorkspaceRepository();
    final controller = buildController(repository);
    addTearDown(repository.dispose);
    await controller.initialize();
    await controller.openPath('a.txt');
    await controller.openPath('b.txt');
    await controller.openPath('c.txt');
    final b = controller.documents[1];
    await controller.activateTab(b);
    b.editorController.text = '本地修改';
    repository.revision = 2;
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump();
    expect(b.saveStatus, DocumentSaveStatus.conflict);

    final stuck = await controller.closeOthers(controller.tabs[0]); // keep a

    expect(stuck, hasLength(1));
    expect(stuck.single.relativePath, 'b.txt');
    // keep a 保留、冲突 b 跳过保留、干净的 c 被关闭。
    expect(controller.tabs.map((t) => t.relativePath).toList(), [
      'a.txt',
      'b.txt',
    ]);
    controller.dispose();
  });

  // ---- 会话恢复产生的 DeferredDocument 与批量关闭的交互 ----
  // 回归：close(活动)→unawaited(activateTab(Deferred 邻居))→close(邻居) 曾与
  // _loadDeferredDocument 的异步重插/dispose 竞态，导致泄漏幽灵 tab 或重复 dispose。

  testWidgets('closeAllTabs empties restored deferred tabs without leaking', (
    tester,
  ) async {
    // 会话恢复：a 为活动（加载为 OpenDocument），b/c 保持 DeferredDocument 占位。
    final sessions = _MemorySessionRepository(
      value: const WorkspaceSessionSnapshot(
        documents: [
          WorkspaceDocumentState(
            relativePath: 'a.txt',
            selectionBase: 0,
            selectionExtent: 0,
            scrollOffset: 0,
          ),
          WorkspaceDocumentState(
            relativePath: 'b.txt',
            selectionBase: 0,
            selectionExtent: 0,
            scrollOffset: 0,
          ),
          WorkspaceDocumentState(
            relativePath: 'c.txt',
            selectionBase: 0,
            selectionExtent: 0,
            scrollOffset: 0,
          ),
        ],
        activePath: 'a.txt',
      ),
    );
    final repository = _MemoryWorkspaceRepository();
    final controller = WorkspaceController(
      session: session,
      service: LibraryWorkspaceService(
        treeRepository: repository,
        documentRepository: repository,
        sessionRepository: sessions,
      ),
    );
    addTearDown(repository.dispose);
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(controller.tabs, hasLength(3));
    expect(controller.documents, hasLength(1)); // 仅活动 a 加载，b/c 为 Deferred。

    final stuck = await controller.closeAllTabs();
    await tester.pump(const Duration(milliseconds: 700));

    expect(stuck, isEmpty);
    expect(controller.tabs, isEmpty);
    expect(controller.activePath, isNull);
  });

  testWidgets('closeOthers keeps the target tab among deferred neighbors', (
    tester,
  ) async {
    final sessions = _MemorySessionRepository(
      value: const WorkspaceSessionSnapshot(
        documents: [
          WorkspaceDocumentState(
            relativePath: 'a.txt',
            selectionBase: 0,
            selectionExtent: 0,
            scrollOffset: 0,
          ),
          WorkspaceDocumentState(
            relativePath: 'b.txt',
            selectionBase: 0,
            selectionExtent: 0,
            scrollOffset: 0,
          ),
          WorkspaceDocumentState(
            relativePath: 'c.txt',
            selectionBase: 0,
            selectionExtent: 0,
            scrollOffset: 0,
          ),
        ],
        activePath: 'a.txt',
      ),
    );
    final repository = _MemoryWorkspaceRepository();
    final controller = WorkspaceController(
      session: session,
      service: LibraryWorkspaceService(
        treeRepository: repository,
        documentRepository: repository,
        sessionRepository: sessions,
      ),
    );
    addTearDown(repository.dispose);
    addTearDown(controller.dispose);
    await controller.initialize();
    // tabs = [OpenA(活动), DeferredB, DeferredC]；保留 c（Deferred）。
    final keep = controller.tabs[2];

    final stuck = await controller.closeOthers(keep);
    await tester.pump(const Duration(milliseconds: 700));

    expect(stuck, isEmpty);
    expect(controller.tabs, hasLength(1));
    // c 被保留（关 a 时激活邻居 c，可能已加载为 OpenDocument，路径不变）。
    expect(controller.tabs.single.relativePath, 'c.txt');
  });

  testWidgets('reorders tabs and moves them between editor groups', (
    tester,
  ) async {
    final repository = _MemoryWorkspaceRepository();
    final controller = buildController(repository);
    addTearDown(repository.dispose);
    await controller.initialize();
    await controller.openPath('a.txt');
    await controller.openPath('b.txt');
    await controller.openPath('c.txt');

    controller.reorderTab(WorkspaceEditorGroupId.primary, 0, 3);
    expect(
      controller
          .tabsForGroup(WorkspaceEditorGroupId.primary)
          .map((tab) => tab.relativePath),
      ['b.txt', 'c.txt', 'a.txt'],
    );

    final moved = controller.tabsForGroup(WorkspaceEditorGroupId.primary).first;
    controller.splitRight(moved);

    expect(controller.isSplit, isTrue);
    expect(controller.focusedGroupId, WorkspaceEditorGroupId.secondary);
    expect(
      controller.tabsForGroup(WorkspaceEditorGroupId.secondary).single,
      same(moved),
    );
    expect(
      controller.activePathForGroup(WorkspaceEditorGroupId.secondary),
      'b.txt',
    );

    controller.moveTab(moved, WorkspaceEditorGroupId.primary, index: 1);

    expect(controller.isSplit, isFalse);
    expect(
      controller
          .tabsForGroup(WorkspaceEditorGroupId.primary)
          .map((tab) => tab.relativePath),
      ['c.txt', 'b.txt', 'a.txt'],
    );
    controller.dispose();
  });

  testWidgets('moving a deferred tab to split loads its document', (
    tester,
  ) async {
    // 回归：重启后会话恢复的标签为延迟文档（仅活动标签读盘，其余占位）。
    // 把未活动的延迟标签拖到右侧分屏时，它成为目标组活动标签却仍延迟，
    // activeDocumentForGroup 返回 null → 内容区显示空态（已选择一个书库项目）。
    // 修复：跨组移动延迟标签时按 activateTab 异步读盘加载后再渲染。
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
    addTearDown(controller.dispose);

    await controller.initialize();
    expect(controller.tabs, hasLength(2));
    expect(controller.documents, hasLength(1)); // 仅活动「一」读盘，「二」延迟。
    expect(repository.readPaths, ['一.txt']);

    // 未活动的「二」仍是延迟文档；拖到右侧分屏（等价 moveTab(deferred, secondary)）。
    final deferred = controller.tabs.last;
    controller.splitRight(deferred);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 600)); // 会话保存(500ms) 定时器落地

    expect(controller.isSplit, isTrue);
    // 修复后：延迟标签跨组移动后被读盘加载，目标组活动文档可渲染（非空）。
    expect(
      controller.activeDocumentForGroup(WorkspaceEditorGroupId.secondary),
      isNotNull,
    );
    expect(
      controller
          .activeDocumentForGroup(WorkspaceEditorGroupId.secondary)!
          .relativePath,
      '二.txt',
    );
    expect(repository.readPaths, ['一.txt', '二.txt']);
  });

  testWidgets('restores both visible editor groups and their active tabs', (
    tester,
  ) async {
    final repository = _MemoryWorkspaceRepository();
    final sessions = _MemorySessionRepository(
      value: const WorkspaceSessionSnapshot(
        documents: [
          WorkspaceDocumentState(
            relativePath: 'left.txt',
            selectionBase: 0,
            selectionExtent: 0,
            scrollOffset: 0,
          ),
          WorkspaceDocumentState(
            relativePath: 'right.txt',
            selectionBase: 0,
            selectionExtent: 0,
            scrollOffset: 0,
          ),
        ],
        activePath: 'right.txt',
        editorGroups: [
          WorkspaceEditorGroupState(
            id: WorkspaceEditorGroupId.primary,
            tabPaths: ['left.txt'],
            activePath: 'left.txt',
          ),
          WorkspaceEditorGroupState(
            id: WorkspaceEditorGroupId.secondary,
            tabPaths: ['right.txt'],
            activePath: 'right.txt',
          ),
        ],
        focusedGroupId: WorkspaceEditorGroupId.secondary,
        splitRatio: 0.6,
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

    expect(controller.isSplit, isTrue);
    expect(controller.documents, hasLength(2));
    expect(repository.readPaths, ['left.txt', 'right.txt']);
    expect(
      controller.activePathForGroup(WorkspaceEditorGroupId.primary),
      'left.txt',
    );
    expect(
      controller.activePathForGroup(WorkspaceEditorGroupId.secondary),
      'right.txt',
    );
    expect(controller.focusedGroupId, WorkspaceEditorGroupId.secondary);
    expect(controller.splitRatio, 0.6);
    controller.dispose();
  });

  testWidgets('collapses restored secondary group when its tab cannot load', (
    tester,
  ) async {
    final repository = _MemoryWorkspaceRepository()..sourceMissing = true;
    final sessions = _MemorySessionRepository(
      value: const WorkspaceSessionSnapshot(
        documents: [
          WorkspaceDocumentState(
            relativePath: 'left.txt',
            selectionBase: 0,
            selectionExtent: 0,
            scrollOffset: 0,
          ),
          WorkspaceDocumentState(
            relativePath: '章节.txt',
            selectionBase: 0,
            selectionExtent: 0,
            scrollOffset: 0,
          ),
        ],
        activePath: '章节.txt',
        editorGroups: [
          WorkspaceEditorGroupState(
            id: WorkspaceEditorGroupId.primary,
            tabPaths: ['left.txt'],
            activePath: 'left.txt',
          ),
          WorkspaceEditorGroupState(
            id: WorkspaceEditorGroupId.secondary,
            tabPaths: ['章节.txt'],
            activePath: '章节.txt',
          ),
        ],
        focusedGroupId: WorkspaceEditorGroupId.secondary,
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

    expect(controller.isSplit, isFalse);
    expect(controller.focusedGroupId, WorkspaceEditorGroupId.primary);
    expect(controller.tabs.map((tab) => tab.relativePath), ['left.txt']);
    expect(controller.activePath, 'left.txt');
    controller.dispose();
  });

  test(
    'saveGeneratedOutline writes categorized files and opens the outline',
    () async {
      final repository = _MemoryWorkspaceRepository();
      final snapshot = _chapterNovelSnapshot();
      final controller = WorkspaceController(
        session: session,
        service: LibraryWorkspaceService(
          treeRepository: repository,
          documentRepository: repository,
          sessionRepository: _MemorySessionRepository(),
        ),
        novelStructureService: NovelStructureService(
          novelRepository: _FakeNovelRepository(snapshot),
          contentTreeRepository: _FakeContentTreeRepository(snapshot),
        ),
      );
      addTearDown(repository.dispose);
      addTearDown(controller.dispose);
      await controller.initialize();

      const outline = GeneratedOutline(
        worldSection: '灵气复苏的东方世界。',
        characterSection: '林晚：孤僻天才。',
        chaptersSection: '# 卷章大纲\n\n## 第一卷\n### 第1章 觉醒\n（一句话情节）',
      );
      final entry = await controller.saveGeneratedOutline(
        novelId: const NovelId('novel-1'),
        outline: outline,
        stem: '龙渊纪元',
      );

      expect(entry.relativePath, '我的小说/大纲/龙渊纪元.md');
      expect(
        repository.createdDocuments.keys,
        containsAll([
          '我的小说/世界观/龙渊纪元-世界观.md',
          '我的小说/人物/龙渊纪元-人物.md',
          '我的小说/大纲/龙渊纪元.md',
        ]),
      );
      expect(
        repository.createdDocuments['我的小说/世界观/龙渊纪元-世界观.md'],
        startsWith('# 世界观'),
      );
      expect(
        repository.createdDocuments['我的小说/人物/龙渊纪元-人物.md'],
        contains('林晚：孤僻天才。'),
      );
      expect(repository.createdDocuments['我的小说/大纲/龙渊纪元.md'], contains('第一卷'));
      // 卷章大纲文件被选中并打开。
      expect(controller.activePath, '我的小说/大纲/龙渊纪元.md');
    },
  );

  test('saveGeneratedOutline skips empty category sections', () async {
    final repository = _MemoryWorkspaceRepository();
    final snapshot = _chapterNovelSnapshot();
    final controller = WorkspaceController(
      session: session,
      service: LibraryWorkspaceService(
        treeRepository: repository,
        documentRepository: repository,
        sessionRepository: _MemorySessionRepository(),
      ),
      novelStructureService: NovelStructureService(
        novelRepository: _FakeNovelRepository(snapshot),
        contentTreeRepository: _FakeContentTreeRepository(snapshot),
      ),
    );
    addTearDown(repository.dispose);
    addTearDown(controller.dispose);
    await controller.initialize();

    final entry = await controller.saveGeneratedOutline(
      novelId: const NovelId('novel-1'),
      outline: const GeneratedOutline(
        worldSection: '',
        characterSection: '',
        chaptersSection: '# 卷章大纲\n\n正文',
      ),
      stem: '只有卷章',
    );

    expect(repository.createdDocuments.keys, ['我的小说/大纲/只有卷章.md']);
    expect(entry.relativePath, '我的小说/大纲/只有卷章.md');
  });

  test(
    'saveGeneratedOutline dedupes stem across the three directories',
    () async {
      final tree = _SeededTreeRepository(
        seeded: {
          '我的小说/世界观': ['龙渊-世界观.md'],
        },
      );
      final repository = _MemoryWorkspaceRepository();
      final snapshot = _chapterNovelSnapshot();
      final controller = WorkspaceController(
        session: session,
        service: LibraryWorkspaceService(
          treeRepository: tree,
          documentRepository: repository,
          sessionRepository: _MemorySessionRepository(),
        ),
        novelStructureService: NovelStructureService(
          novelRepository: _FakeNovelRepository(snapshot),
          contentTreeRepository: _FakeContentTreeRepository(snapshot),
        ),
      );
      addTearDown(repository.dispose);
      addTearDown(controller.dispose);
      await controller.initialize();

      final entry = await controller.saveGeneratedOutline(
        novelId: const NovelId('novel-1'),
        outline: const GeneratedOutline(
          worldSection: '世界',
          characterSection: '人物',
          chaptersSection: '卷章',
        ),
        stem: '龙渊',
      );

      expect(entry.relativePath, '我的小说/大纲/龙渊-2.md');
      expect(
        tree.created.keys,
        containsAll([
          '我的小说/世界观/龙渊-2-世界观.md',
          '我的小说/人物/龙渊-2-人物.md',
          '我的小说/大纲/龙渊-2.md',
        ]),
      );
    },
  );
}

final class _MemoryWorkspaceRepository
    implements LibraryTreeRepository, DocumentRepository, HighlightRepository {
  _MemoryWorkspaceRepository({this.emitAtomicReplacementEventsOnSave = false});

  final bool emitAtomicReplacementEventsOnSave;
  final changes = StreamController<DocumentChange>.broadcast();
  final savedTexts = <String>[];
  final readPaths = <String>[];
  final createdDocuments = <String, String>{};
  String diskText = '原文';
  int revision = 1;
  bool sourceMissing = false;

  /// 内存高亮存储：documentId → 集合。模拟 `<novel>/.lore/highlights.json` 按
  /// 文档索引的落盘语义（deleteHighlights 移除整个 documentId 条目）。
  final Map<String, HighlightCollection> highlightsByDocument = {};

  /// 若非 null，下一次 [saveDocument] 会等待此 Completer 完成后再继续，
  /// 便于测试在保存进行中插入编辑（复现副标题保存竞态）。仅消费一次。
  Completer<void>? saveGate;

  Future<void> dispose() => changes.close();

  // ---- HighlightRepository（内存实现，测试用） ----

  @override
  Future<HighlightCollection?> loadHighlights(
    LibraryAccess access, {
    required NovelId novelId,
    required String documentId,
  }) async {
    return highlightsByDocument[documentId];
  }

  @override
  Future<void> saveHighlights(
    LibraryAccess access, {
    required NovelId novelId,
    required String documentId,
    required HighlightCollection collection,
  }) async {
    highlightsByDocument[documentId] = collection;
  }

  @override
  Future<void> deleteHighlights(
    LibraryAccess access, {
    required NovelId novelId,
    required String documentId,
  }) async {
    highlightsByDocument.remove(documentId);
  }

  @override
  Future<void> moveHighlights(
    LibraryAccess access, {
    required NovelId novelId,
    required String oldDocumentId,
    required String newDocumentId,
  }) async {
    if (oldDocumentId == newDocumentId) return;
    final existing = highlightsByDocument.remove(oldDocumentId);
    if (existing != null) {
      highlightsByDocument[newDocumentId] = existing;
    }
  }

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

/// 可预置目录内容的内存目录树仓库：按 `relativePath` 返回该目录下已存在的文件
/// 列表，记录创建的文件；`renameEntry`/`deleteEntry` 在目录树相关测试中未用到。
final class _SeededTreeRepository implements LibraryTreeRepository {
  _SeededTreeRepository({Map<String, List<String>>? seeded})
    : files = {
        for (final entry in (seeded ?? const {}).entries)
          entry.key: List.of(entry.value),
      };

  /// 目录 relativePath → 目录下已有的文件/子目录名。
  final Map<String, List<String>> files;

  /// 创建的文件：relativePath → initialText。
  final created = <String, String>{};

  @override
  Future<List<LibraryEntry>> listChildren(
    LibraryAccess access, {
    String relativePath = '',
  }) async {
    final names = files[relativePath] ?? const <String>[];
    return [
      for (final name in names)
        LibraryEntry(
          name: name,
          relativePath: relativePath.isEmpty ? name : '$relativePath/$name',
          type: name.endsWith('.md')
              ? LibraryEntryType.markdownFile
              : LibraryEntryType.directory,
        ),
    ];
  }

  @override
  Future<LibraryEntry> createDirectory(
    LibraryAccess access, {
    required String parentPath,
    required String name,
  }) async {
    final relativePath = parentPath.isEmpty ? name : '$parentPath/$name';
    files[relativePath] ??= <String>[];
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
    created[relativePath] = initialText;
    (files[parentPath] ??= <String>[]).add(fileName);
    return LibraryEntry(
      name: fileName,
      relativePath: relativePath,
      type: format == DocumentFormat.text
          ? LibraryEntryType.textFile
          : LibraryEntryType.markdownFile,
    );
  }

  @override
  Future<LibraryEntry> renameEntry(
    LibraryAccess access, {
    required String relativePath,
    required String newName,
  }) {
    throw UnimplementedError('renameEntry');
  }

  @override
  Future<DeletionResult> deleteEntry(
    LibraryAccess access, {
    required String relativePath,
  }) {
    throw UnimplementedError('deleteEntry');
  }
}

/// 仅返回默认偏好的 [AppPreferencesRepository]，供 DocumentPane 组件测试免去
/// SharedPreferences 落库依赖（真实 [PreferencesController] 在其上运行）。
class _DefaultsPrefsRepository implements AppPreferencesRepository {
  @override
  Future<AppPreferences?> load() async => AppPreferences.defaults();

  @override
  Future<void> save(AppPreferences preferences) async {}

  @override
  Stream<AppPreferences> watch() => const Stream.empty();
}

NovelSnapshot _chapterNovelSnapshot({
  String chapterRelativePath = '正文/第1章.txt',
  int chapterNumber = 1,
  int? characterCount,
}) {
  final novelId = NovelId('novel-1');
  final bodyId = ContentId('body');
  final chapterId = ContentId('chapter-1');
  return NovelSnapshot(
    rootPath: '我的小说',
    metadata: NovelMetadata(
      schemaVersion: 2,
      id: novelId,
      title: '我的小说',
      description: '',
      coverPath: null,
      body: NovelBody(id: bodyId, relativePath: '正文'),
      chapterFormat: ChapterFormat.text,
      numberingMode: NumberingMode.continuous,
      createdAt: DateTime.utc(2026, 7, 17),
      updatedAt: DateTime.utc(2026, 7, 17),
    ),
    contentTree: ContentTree(
      schemaVersion: 2,
      novelId: novelId,
      revision: 1,
      nodes: [
        ContentNode(
          id: chapterId,
          type: ContentNodeType.chapter,
          parentId: bodyId,
          relativePath: chapterRelativePath,
          order: 1000,
          number: chapterNumber,
          role: ContentRole.normal,
          characterCount: characterCount,
        ),
      ],
    ),
  );
}

class _FakeNovelRepository implements NovelRepository {
  _FakeNovelRepository(this.novel);

  NovelSnapshot novel;

  @override
  Future<List<NovelSnapshot>> listNovels(LibraryAccess access) async => [novel];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('_FakeNovelRepository.${invocation.memberName}');
}

class _FakeContentTreeRepository implements ContentTreeRepository {
  _FakeContentTreeRepository(this.novel, {this.watchSink});

  NovelSnapshot novel;

  /// 若提供，重命名时向其推送 watch 事件（delete 旧路径 + create 新路径），
  /// 模拟真实存储层文件监听在 storage.move 后的回流，供控制器 _handleDocumentChange 走通。
  final StreamController<DocumentChange>? watchSink;

  String? lastRenameNewName;
  ContentId? lastRenameNodeId;
  Map<ContentId, int>? lastCharacterCounts;

  @override
  Future<NovelStructureMutation> renameNode(
    LibraryAccess access, {
    required NovelId novelId,
    required ContentId nodeId,
    required String newName,
  }) async {
    lastRenameNewName = newName;
    lastRenameNodeId = nodeId;
    final oldNode = novel.contentTree.nodeById(nodeId);
    if (oldNode == null) {
      throw StateError('chapter node not found: $nodeId');
    }
    final oldRel = oldNode.relativePath;
    final dir = p.dirname(oldRel);
    final ext = p.extension(oldRel);
    final newRel = dir == '.' ? '$newName$ext' : '$dir/$newName$ext';
    // 按新文件名重算 number（与真实存储层 _renumberNode 一致），供控制器
    // _syncOpenChapterNumbers 据此刷新已打开标签的锁定前缀编号。
    final stemMatch = RegExp(r'^第(\d+)章').firstMatch(newName);
    final newNumber = stemMatch == null ? null : int.parse(stemMatch.group(1)!);
    final renamed = ContentNode(
      id: oldNode.id,
      type: oldNode.type,
      parentId: oldNode.parentId,
      relativePath: newRel,
      order: oldNode.order,
      number: newNumber,
      role: oldNode.role,
    );
    final newTree = ContentTree(
      schemaVersion: novel.contentTree.schemaVersion,
      novelId: novel.contentTree.novelId,
      revision: novel.contentTree.revision + 1,
      nodes: novel.contentTree.nodes
          .map((node) => node.id == nodeId ? renamed : node)
          .toList(growable: false),
    );
    novel = NovelSnapshot(
      rootPath: novel.rootPath,
      metadata: novel.metadata,
      contentTree: newTree,
    );
    final oldPath = p.join(novel.rootPath, oldRel);
    final newPath = p.join(novel.rootPath, newRel);
    // 模拟真实存储层在 storage.move 后推送的文件监听事件（delete 旧 + create 新）。
    final sink = watchSink;
    if (sink != null && !sink.isClosed) {
      sink.add(
        DocumentChange(relativePath: oldPath, type: DocumentChangeType.deleted),
      );
      sink.add(
        DocumentChange(relativePath: newPath, type: DocumentChangeType.created),
      );
    }
    return NovelStructureMutation(
      snapshot: novel,
      entry: LibraryEntry(
        name: '$newName$ext',
        relativePath: newPath,
        type: LibraryEntryType.textFile,
        semanticKind: LibraryEntrySemanticKind.chapter,
        semanticId: nodeId.value,
        novelId: novel.metadata.id.value,
        semanticOrder: oldNode.order,
      ),
      pathChanges: [PathChange(oldPath: oldPath, newPath: newPath)],
    );
  }

  @override
  Future<NovelReconciliationResult> reconcile(
    LibraryAccess access, {
    required NovelId novelId,
  }) async => NovelReconciliationResult(snapshot: novel);

  @override
  Future<NovelStructureMutation> updateChapterCharacterCounts(
    LibraryAccess access, {
    required NovelId novelId,
    required Map<ContentId, int> characterCounts,
  }) async {
    lastCharacterCounts = characterCounts;
    final newTree = ContentTree(
      schemaVersion: novel.contentTree.schemaVersion,
      novelId: novel.contentTree.novelId,
      revision: novel.contentTree.revision + 1,
      nodes: novel.contentTree.nodes
          .map(
            (node) => node.type == ContentNodeType.chapter
                ? node.copyWith(characterCount: characterCounts[node.id])
                : node,
          )
          .toList(growable: false),
    );
    novel = NovelSnapshot(
      rootPath: novel.rootPath,
      metadata: novel.metadata,
      contentTree: newTree,
    );
    return NovelStructureMutation(snapshot: novel);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '_FakeContentTreeRepository.${invocation.memberName}',
  );
}
