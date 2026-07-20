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

  test('controller uses the indexed directory fast path', () async {
    final repository = _IndexedWorkspaceRepository();
    final controller = _controller(session, repository);
    addTearDown(controller.dispose);
    await controller.initialize();

    final entries = await controller.listChildren();

    expect(entries.single.name, '快速路径.md');
    expect(repository.indexedRequests, 1);
    expect(repository.regularRequests, 0);
  });

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

  testWidgets('hides .txt extension for text files in the tree', (
    tester,
  ) async {
    final repository = _PathWorkspaceRepository({
      '': const [
        LibraryEntry(
          name: '笔记.txt',
          relativePath: '笔记.txt',
          type: LibraryEntryType.textFile,
        ),
        LibraryEntry(
          name: '资料.md',
          relativePath: '资料.md',
          type: LibraryEntryType.markdownFile,
        ),
      ],
    });
    final controller = _controller(session, repository);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_tree(controller, reloadToken: 0));
    await tester.pump();
    await tester.pump();

    expect(find.text('笔记'), findsOneWidget);
    expect(find.text('笔记.txt'), findsNothing);
    expect(find.text('资料.md'), findsOneWidget);
  });

  testWidgets('hides .txt extension for chapter text files', (tester) async {
    final repository = _PathWorkspaceRepository({
      '': const [
        LibraryEntry(
          name: '第1章.txt',
          relativePath: '第1章.txt',
          type: LibraryEntryType.textFile,
          semanticKind: LibraryEntrySemanticKind.chapter,
        ),
      ],
    });
    final controller = _controller(session, repository);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_tree(controller, reloadToken: 0));
    await tester.pump();
    await tester.pump();

    expect(find.text('第1章'), findsOneWidget);
    expect(find.text('第1章.txt'), findsNothing);
  });

  testWidgets('does not show placeholder for empty expanded folders', (
    tester,
  ) async {
    final repository = _PathWorkspaceRepository({
      '': const [
        LibraryEntry(
          name: '空文件夹',
          relativePath: '空文件夹',
          type: LibraryEntryType.directory,
        ),
      ],
    });
    final controller = _controller(session, repository);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_tree(controller, reloadToken: 0));
    await tester.pump();
    await tester.pump();

    expect(find.text('文件夹为空'), findsNothing);

    await tester.tap(find.text('空文件夹'));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('文件夹为空'), findsNothing);
  });

  testWidgets('does not reserve layout space while lazy-loading a folder', (
    tester,
  ) async {
    // 展开一个尚未加载完成的目录时，加载中间帧不得占位——否则空目录
    // 展开会先挤出进度条（~10px）再在加载完成时收回，造成一帧布局抖动。
    final childLoaded = Completer<List<LibraryEntry>>();
    final repository = _QueuedWorkspaceRepository([
      Future.value(const [
        LibraryEntry(
          name: '空文件夹',
          relativePath: '空文件夹',
          type: LibraryEntryType.directory,
        ),
      ]),
      childLoaded.future,
    ]);
    final controller = _controller(session, repository);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_tree(controller, reloadToken: 0));
    await tester.pump();

    await tester.tap(find.text('空文件夹'));
    await tester.pump();

    // 子目录 Future 尚未完成（loading 中间帧）：不应出现任何进度条占位。
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    childLoaded.complete(const []);
    await tester.pump();
    await tester.pump();

    // 加载完成且目录为空：仍无占位。
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('deduplicates an in-flight directory load when reopened', (
    tester,
  ) async {
    final childLoaded = Completer<List<LibraryEntry>>();
    final repository = _QueuedWorkspaceRepository([
      Future.value(const [
        LibraryEntry(
          name: '卷一',
          relativePath: '卷一',
          type: LibraryEntryType.directory,
        ),
      ]),
      childLoaded.future,
    ]);
    final controller = _controller(session, repository);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_tree(controller, reloadToken: 0));
    await tester.pump();
    await tester.tap(find.text('卷一'));
    await tester.pump();
    await tester.tap(find.text('卷一'));
    await tester.pump();
    await tester.tap(find.text('卷一'));
    await tester.pump();

    expect(repository.requests.where((path) => path == '卷一'), hasLength(1));

    childLoaded.complete(const []);
    await tester.pump();
  });

  testWidgets('clamps scrolling to avoid overscroll bounce', (tester) async {
    final repository = _PathWorkspaceRepository({
      '': const [
        LibraryEntry(
          name: '卷一',
          relativePath: '卷一',
          type: LibraryEntryType.directory,
        ),
      ],
    });
    final controller = _controller(session, repository);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_tree(controller, reloadToken: 0));
    await tester.pump();

    // 根目录树渲染为唯一的 ListView；其 physics 应为 ClampingScrollPhysics，
    // 避免在 macOS 上到边界出现弹性过滚。
    expect(find.byType(ListView), findsOneWidget);
    final listView = tester.widget<ListView>(find.byType(ListView));
    expect(listView.physics, isA<ClampingScrollPhysics>());
  });

  testWidgets('does not tooltip names that fit without truncation', (
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
    });
    final controller = _controller(session, repository);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_tree(controller, reloadToken: 0));
    await tester.pump();

    // 名字完整显示时不应挂 tooltip，避免 hover 弹出重复提示；
    // 仅在超长被截断时才显示（由 _OverflowTooltip 控制）。
    expect(find.byTooltip('卷一'), findsNothing);
  });

  testWidgets('virtualizes large directories to visible rows', (tester) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _PathWorkspaceRepository({
      '': List.generate(
        5000,
        (index) => LibraryEntry(
          name: '文件$index.md',
          relativePath: '文件$index.md',
          type: LibraryEntryType.markdownFile,
        ),
      ),
    });
    final controller = _controller(session, repository);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_tree(controller, reloadToken: 0));
    await tester.pump();

    expect(find.text('文件0.md'), findsOneWidget);
    expect(find.text('文件4999.md'), findsNothing);
    expect(find.byType(InkWell).evaluate().length, lessThan(100));

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pump();

    expect(find.text('文件0.md'), findsNothing);
    expect(find.text('文件4999.md'), findsOneWidget);
  });

  testWidgets('reuses loaded children after collapsing and reopening', (
    tester,
  ) async {
    final repository = _CountingWorkspaceRepository({
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
    await tester.tap(find.text('卷一'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('卷一'));
    await tester.pump();
    await tester.tap(find.text('卷一'));
    await tester.pump();

    expect(find.text('第一章.md'), findsOneWidget);
    expect(repository.requests.where((path) => path == '卷一'), hasLength(1));
  });

  testWidgets('invalidates collapsed caches without refreshing them', (
    tester,
  ) async {
    final repository = _CountingWorkspaceRepository({
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
    await tester.tap(find.text('卷一'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('卷一'));
    await tester.pump();

    await tester.pumpWidget(_tree(controller, reloadToken: 1));
    await tester.pump();

    expect(repository.requests.where((path) => path.isEmpty), hasLength(2));
    expect(repository.requests.where((path) => path == '卷一'), hasLength(1));

    await tester.tap(find.text('卷一'));
    await tester.pump();
    await tester.pump();

    expect(repository.requests.where((path) => path == '卷一'), hasLength(2));
  });

  testWidgets('bounds restored directory preload concurrency', (tester) async {
    final repository = _ControlledWorkspaceRepository();
    final controller = _controller(session, repository);
    for (var index = 0; index < 12; index += 1) {
      controller.setDirectoryExpanded('目录$index', true);
    }
    addTearDown(controller.dispose);

    await tester.pumpWidget(_tree(controller, reloadToken: 0));

    expect(repository.requests, hasLength(6));
    expect(repository.maximumActiveRequests, 6);

    for (
      var round = 0;
      round < 3 && repository.requests.length < 13;
      round += 1
    ) {
      repository.completeActiveRequests();
      await tester.pump();
    }
    repository.completeActiveRequests();
    await tester.pump();

    expect(repository.requests.toSet(), hasLength(13));
    expect(repository.maximumActiveRequests, 6);
  });

  testWidgets('prioritizes an expanded directory already queued for preload', (
    tester,
  ) async {
    final entries = List.generate(
      12,
      (index) => LibraryEntry(
        name: '目录$index',
        relativePath: '目录$index',
        type: LibraryEntryType.directory,
      ),
    );
    final repository = _ControlledWorkspaceRepository(
      immediateEntries: {'': entries},
    );
    final controller = _controller(session, repository);
    for (final entry in entries) {
      controller.setDirectoryExpanded(entry.relativePath, true);
    }
    addTearDown(controller.dispose);

    await tester.pumpWidget(_tree(controller, reloadToken: 0));
    await tester.pump();

    expect(
      repository.requests,
      containsAll(entries.take(6).map((e) => e.relativePath)),
    );
    expect(repository.requests, isNot(contains('目录11')));

    await tester.tap(find.text('目录11'));
    await tester.pump();
    await tester.tap(find.text('目录11'));
    await tester.pump();
    repository.completePath('目录0');
    await tester.pump();

    expect(repository.requests.last, '目录11');
    repository.completeActiveRequests();
    await tester.pump();
  });

  testWidgets('keeps the load limit across controller generations', (
    tester,
  ) async {
    final tracker = _DirectoryLoadTracker();
    final firstRepository = _ControlledWorkspaceRepository(tracker: tracker);
    final firstController = _controller(session, firstRepository);
    for (var index = 0; index < 5; index += 1) {
      firstController.setDirectoryExpanded('旧目录$index', true);
    }
    addTearDown(firstController.dispose);

    await tester.pumpWidget(_tree(firstController, reloadToken: 0));
    expect(tracker.activeRequestCount, 6);

    final secondRepository = _ControlledWorkspaceRepository(tracker: tracker);
    final secondController = _controller(session, secondRepository);
    addTearDown(secondController.dispose);
    await tester.pumpWidget(_tree(secondController, reloadToken: 0));

    expect(secondRepository.requests, isEmpty);
    expect(tracker.maximumActiveRequests, 6);

    firstRepository.completePath('');
    await tester.pump();

    expect(secondRepository.requests, ['']);
    expect(tracker.maximumActiveRequests, 6);
    firstRepository.completeActiveRequests();
    secondRepository.completeActiveRequests();
    await tester.pump();
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
  final List<String> requests = [];

  @override
  Future<List<LibraryEntry>> listChildren(
    LibraryAccess access, {
    String relativePath = '',
  }) {
    requests.add(relativePath);
    return responses.removeAt(0);
  }
}

base class _PathWorkspaceRepository extends _WorkspaceRepository {
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

final class _CountingWorkspaceRepository extends _PathWorkspaceRepository {
  _CountingWorkspaceRepository(super.entries);

  final List<String> requests = [];

  @override
  Future<List<LibraryEntry>> listChildren(
    LibraryAccess access, {
    String relativePath = '',
  }) {
    requests.add(relativePath);
    return super.listChildren(access, relativePath: relativePath);
  }
}

final class _IndexedWorkspaceRepository extends _WorkspaceRepository
    implements IndexedLibraryTreeRepository {
  int regularRequests = 0;
  int indexedRequests = 0;

  @override
  Future<List<LibraryEntry>> listChildren(
    LibraryAccess access, {
    String relativePath = '',
  }) async {
    regularRequests += 1;
    return const [];
  }

  @override
  Future<List<LibraryEntry>> listChildrenWithSemanticEntries(
    LibraryAccess access, {
    required Map<String, LibraryEntry> semanticEntries,
    String relativePath = '',
  }) async {
    indexedRequests += 1;
    return const [
      LibraryEntry(
        name: '快速路径.md',
        relativePath: '快速路径.md',
        type: LibraryEntryType.markdownFile,
      ),
    ];
  }
}

final class _ControlledWorkspaceRepository extends _WorkspaceRepository {
  _ControlledWorkspaceRepository({
    this.immediateEntries = const {},
    _DirectoryLoadTracker? tracker,
  }) : tracker = tracker ?? _DirectoryLoadTracker();

  final Map<String, List<LibraryEntry>> immediateEntries;
  final _DirectoryLoadTracker tracker;
  final List<String> requests = [];
  final Map<String, Completer<List<LibraryEntry>>> _activeRequests = {};

  int get activeRequestCount => tracker.activeRequestCount;

  int get maximumActiveRequests => tracker.maximumActiveRequests;

  @override
  Future<List<LibraryEntry>> listChildren(
    LibraryAccess access, {
    String relativePath = '',
  }) {
    requests.add(relativePath);
    final immediate = immediateEntries[relativePath];
    if (immediate != null) {
      return Future.value(immediate);
    }
    tracker.start();
    final completer = Completer<List<LibraryEntry>>();
    _activeRequests[relativePath] = completer;
    return completer.future.whenComplete(tracker.complete);
  }

  void completePath(String path) {
    final completer = _activeRequests.remove(path);
    if (completer != null && !completer.isCompleted) {
      completer.complete(const []);
    }
  }

  void completeActiveRequests() {
    final completers = _activeRequests.values.toList();
    _activeRequests.clear();
    for (final completer in completers) {
      if (!completer.isCompleted) {
        completer.complete(const []);
      }
    }
  }
}

final class _DirectoryLoadTracker {
  int activeRequestCount = 0;
  int maximumActiveRequests = 0;

  void start() {
    activeRequestCount += 1;
    if (activeRequestCount > maximumActiveRequests) {
      maximumActiveRequests = activeRequestCount;
    }
  }

  void complete() {
    activeRequestCount -= 1;
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
