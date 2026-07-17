import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_storage/lore_storage.dart';

import 'package:lore_app/app/lore_app.dart';
import 'package:lore_app/features/library/library_providers.dart';

void main() {
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

    await tester.tap(find.text('第一章.md'));
    await tester.pumpAndSettle();

    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('预览'), findsOneWidget);
    expect(find.text('已保存'), findsOneWidget);
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
