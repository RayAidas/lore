// Test-only harness for the TXT import/export widget tests.
//
// Test-only helper that intentionally leaks private fake types on its surface
// to keep the tests terse.
// ignore_for_file: library_private_types_in_public_api
//
// Builds an in-memory `WorkspaceController` wired with fakes that cover the
// MINIMAL repository surface touched by `importTxtNovelFlow` and `ExportPanel`:
//   * NovelRepository: importNovel, listNovels, loadNovel
//   * ContentTreeRepository: reconcile (called during initialize)
//   * LibraryTreeRepository / DocumentRepository / WorkspaceSessionRepository:
//     listChildren, readDocument, watchDocuments, saveDocument, createDirectory,
//     createDocument, renameEntry, deleteEntry.
//
// The rest of the port surface throws UnimplementedError — if a test wanders
// off the supported path it fails loudly instead of silently passing.
library;

import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
// FakeFilePickerPlatform needs the abstract class, which file_picker does not
// re-export publicly. The path-level import is acceptable for a test-only
// harness file (it never ships in the app).
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_app/features/workspace/workspace_controller.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:path/path.dart' as p;

/// In-memory novel repository that supports the import + export read paths.
///
/// Each [importNovel] call appends a new snapshot keyed by a stable [NovelId],
/// so `controller.novels` reflects what the import flow produced. The caller
/// can pre-seed novels (used by the export tests) via [snapshots].
class _MemoryNovelRepository implements NovelRepository {
  _MemoryNovelRepository({List<NovelSnapshot>? initial})
    : snapshots = initial ?? <NovelSnapshot>[];

  final List<NovelSnapshot> snapshots;
  final List<String> importedTitles = <String>[];

  @override
  Future<List<NovelSnapshot>> listNovels(LibraryAccess access) async =>
      List<NovelSnapshot>.unmodifiable(snapshots);

  @override
  Future<NovelSnapshot> loadNovel(
    LibraryAccess access, {
    required NovelId novelId,
  }) async {
    return snapshots.firstWhere((s) => s.metadata.id == novelId);
  }

  @override
  Future<NovelStructureMutation> importNovel(
    LibraryAccess access, {
    required String title,
    required List<ParsedSection> sections,
    ChapterFormat chapterFormat = ChapterFormat.text,
  }) async {
    importedTitles.add(title);
    final novelId = NovelId('novel-${snapshots.length + 1}');
    final bodyId = ContentId('body-${snapshots.length + 1}');
    final nodes = <ContentNode>[];
    var order = 1000;
    var chapterIndex = 1;
    for (final section in sections) {
      final chapters = switch (section) {
        ParsedRootChapters(:final chapters) => chapters,
        ParsedVolume(:final chapters) => chapters,
      };
      for (final chapter in chapters) {
        final subtitle = chapter.subtitle.trim();
        final fileName = subtitle.isEmpty
            ? '第$chapterIndex章.txt'
            : '第$chapterIndex章 $subtitle.txt';
        nodes.add(
          ContentNode(
            id: ContentId('chapter-${snapshots.length + 1}-$chapterIndex'),
            type: ContentNodeType.chapter,
            parentId: bodyId,
            relativePath: '正文/$fileName',
            order: order,
            number: chapterIndex,
            role: ContentRole.normal,
          ),
        );
        order += 1000;
        chapterIndex += 1;
      }
    }
    final now = DateTime.utc(2026, 7, 17);
    final snapshot = NovelSnapshot(
      rootPath: title,
      metadata: NovelMetadata(
        schemaVersion: 2,
        id: novelId,
        title: title,
        description: '',
        coverPath: null,
        body: NovelBody(id: bodyId, relativePath: '正文'),
        chapterFormat: ChapterFormat.text,
        numberingMode: NumberingMode.continuous,
        createdAt: now,
        updatedAt: now,
      ),
      contentTree: ContentTree(
        schemaVersion: 2,
        novelId: novelId,
        revision: 1,
        nodes: nodes,
      ),
    );
    snapshots.add(snapshot);
    return NovelStructureMutation(snapshot: snapshot);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '_MemoryNovelRepository.${invocation.memberName}',
  );
}

/// In-memory content-tree repository that only answers `reconcile` (called
/// during controller initialize). Everything else throws.
class _MemoryContentTreeRepository implements ContentTreeRepository {
  _MemoryContentTreeRepository();

  @override
  Future<NovelReconciliationResult> reconcile(
    LibraryAccess access, {
    required NovelId novelId,
  }) async {
    throw UnimplementedError(
      '_MemoryContentTreeRepository.reconcile not seeded for $novelId',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '_MemoryContentTreeRepository.${invocation.memberName}',
  );
}

/// Reconcile-seedable variant: returns the snapshot the controller loaded for
/// each novel during initialize (keeps the load → reconcile loop symmetric).
class _SeededContentTreeRepository implements ContentTreeRepository {
  _SeededContentTreeRepository(this._snapshotFor);

  final NovelSnapshot Function(NovelId) _snapshotFor;

  @override
  Future<NovelReconciliationResult> reconcile(
    LibraryAccess access, {
    required NovelId novelId,
  }) async {
    return NovelReconciliationResult(snapshot: _snapshotFor(novelId));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '_SeededContentTreeRepository.${invocation.memberName}',
  );
}

/// In-memory library tree + document repository used for both import (no reads
/// of chapters) and export (readDocument returns seeded chapter text).
class _MemoryWorkspaceRepository
    implements LibraryTreeRepository, DocumentRepository {
  _MemoryWorkspaceRepository({Map<String, String>? chapterTexts})
    : _chapterTexts = chapterTexts ?? <String, String>{};

  final Map<String, String> _chapterTexts;
  final changes = StreamController<DocumentChange>.broadcast();

  /// Set the on-disk text for a given absolute (root-prefixed) chapter path.
  void setChapterText(String absolutePath, String text) {
    _chapterTexts[absolutePath] = text;
  }

  Future<void> dispose() => changes.close();

  @override
  Future<DocumentSnapshot> readDocument(
    LibraryAccess access,
    DocumentRef ref,
  ) async {
    return DocumentSnapshot(
      ref: ref,
      text: _chapterTexts[ref.relativePath] ?? '',
      encoding: TextEncoding.utf8,
      lineEnding: LineEnding.lf,
      revision: const DocumentRevision('revision-1'),
    );
  }

  @override
  Stream<DocumentChange> watchDocuments(LibraryAccess access) => changes.stream;

  @override
  Future<List<LibraryEntry>> listChildren(
    LibraryAccess access, {
    String relativePath = '',
  }) async => const <LibraryEntry>[];

  @override
  Future<LibraryEntry> createDirectory(
    LibraryAccess access, {
    required String parentPath,
    required String name,
  }) async => LibraryEntry(
    name: name,
    relativePath: parentPath.isEmpty ? name : '$parentPath/$name',
    type: LibraryEntryType.directory,
  );

  @override
  Future<LibraryEntry> createDocument(
    LibraryAccess access, {
    required String parentPath,
    required String name,
    required DocumentFormat format,
    String initialText = '',
  }) async {
    final ext = format == DocumentFormat.text ? '.txt' : '.md';
    final fileName = name.endsWith(ext) ? name : '$name$ext';
    return LibraryEntry(
      name: fileName,
      relativePath: parentPath.isEmpty ? fileName : '$parentPath/$fileName',
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
  }) async => LibraryEntry(
    name: newName,
    relativePath: newName,
    type: LibraryEntryType.textFile,
  );

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
  Future<DeletionResult> deleteEntry(
    LibraryAccess access, {
    required String relativePath,
  }) async => DeletionResult(
    trashToken: 'trash-$relativePath',
    removedNodeIds: const [],
    pathChanges: const [],
  );
}

/// Session repo whose saved snapshot lives in memory; supports restoration.
class _MemorySessionRepository implements WorkspaceSessionRepository {
  _MemorySessionRepository();

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

/// The assembled controller harness.
class ImportExportTestHarness {
  ImportExportTestHarness._({
    required this.controller,
    required this.novelRepository,
    required this.workspaceRepository,
  });

  final WorkspaceController controller;
  final _MemoryNovelRepository novelRepository;
  final _MemoryWorkspaceRepository workspaceRepository;

  /// Titles the import flow forwarded to `NovelRepository.importNovel`, in
  /// call order. Convenience alias for `novelRepository.importedTitles`.
  List<String> get importedTitles => novelRepository.importedTitles;

  /// Build a harness with no pre-seeded novels (import-flow case).
  static Future<ImportExportTestHarness> empty() async =>
      _build(initialNovels: const []);

  /// Build a harness with [snapshot] pre-seeded, for export tests. The chapter
  /// texts map is keyed by absolute path (rootPath + '/' + chapter.relativePath)
  /// and feeds readDocument.
  static Future<ImportExportTestHarness> withNovel(
    NovelSnapshot snapshot, {
    Map<String, String> chapterTexts = const {},
  }) async {
    final harness = await _build(
      initialNovels: [snapshot],
      chapterTexts: chapterTexts,
    );
    return harness;
  }

  static Future<ImportExportTestHarness> _build({
    required List<NovelSnapshot> initialNovels,
    Map<String, String> chapterTexts = const {},
  }) async {
    // 始终复制为可变 List：调用方传入的可能是 const []，importNovel 添加时
    // 会抛 Unsupported operation。
    final growableNovels = <NovelSnapshot>[...initialNovels];
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
    final session = LibrarySession(access: access, metadata: metadata);
    final novelRepository = _MemoryNovelRepository(initial: growableNovels);
    final workspaceRepository = _MemoryWorkspaceRepository(
      chapterTexts: chapterTexts,
    );
    final contentTreeRepository = growableNovels.isEmpty
        ? _MemoryContentTreeRepository()
        : _SeededContentTreeRepository(
            (id) => growableNovels.firstWhere((n) => n.metadata.id == id),
          );
    final controller = WorkspaceController(
      session: session,
      service: LibraryWorkspaceService(
        treeRepository: workspaceRepository,
        documentRepository: workspaceRepository,
        sessionRepository: _MemorySessionRepository(),
      ),
      novelStructureService: NovelStructureService(
        novelRepository: novelRepository,
        contentTreeRepository: contentTreeRepository,
      ),
    );
    await controller.initialize();
    return ImportExportTestHarness._(
      controller: controller,
      novelRepository: novelRepository,
      workspaceRepository: workspaceRepository,
    );
  }

  Future<void> dispose() async {
    controller.dispose();
    await workspaceRepository.dispose();
  }
}

/// Fake file_picker platform singleton. `extends` (not `implements`) so that
/// the platform-interface verifyToken check passes; only overrides pickFiles
/// and saveFile, which are the only paths the import/export flows touch.
class FakeFilePickerPlatform extends FilePickerPlatform {
  /// Scripted return for the next `pickFiles` call. Null cancels the dialog.
  FilePickerResult? pickFilesResult;

  /// Scripted return for the next `saveFile` call. Null cancels the dialog.
  String? saveFilePath;

  /// Captures the bytes passed to the most recent `saveFile` call.
  Uint8List? lastSaveBytes;

  /// Number of times each entry point was invoked — useful for asserting the
  /// flow did (or did not) reach a particular leg.
  int pickFilesCalls = 0;
  int saveFileCalls = 0;

  /// When true, the next `pickFiles`/`saveFile` call throws a [PlatformException]
  /// to exercise the import/export flows' entitlement / channel-failure handling.
  bool shouldThrowOnPickFiles = false;
  bool shouldThrowOnSaveFile = false;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
    bool cancelUploadOnWindowBlur = true,
  }) async {
    pickFilesCalls += 1;
    if (shouldThrowOnPickFiles) {
      throw PlatformException(
        code: 'ENTITLEMENT_NOT_FOUND',
        message: 'test: picker unavailable',
      );
    }
    return pickFilesResult;
  }

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    saveFileCalls += 1;
    if (shouldThrowOnSaveFile) {
      throw PlatformException(
        code: 'ENTITLEMENT_REQUIRED_WRITE',
        message: 'test: saver unavailable',
      );
    }
    lastSaveBytes = bytes;
    return saveFilePath;
  }

  /// Decode the most recent captured bytes back to a UTF-8 string. Returns
  /// null when [lastSaveBytes] is null.
  String? get lastSaveText =>
      lastSaveBytes == null ? null : utf8.decode(lastSaveBytes!);
}

/// Swap in [fake] as the process-global FilePickerPlatform.instance and
/// register a tear-down that restores whatever was there before. Importantly,
/// restoration is unconditional — the platform singleton is process-global
/// and leaking the fake would break unrelated tests in the same run.
FakeFilePickerPlatform installFakeFilePicker(FakeFilePickerPlatform fake) {
  final original = FilePickerPlatform.instance;
  FilePickerPlatform.instance = fake;
  addTearDown(() => FilePickerPlatform.instance = original);
  return fake;
}

/// Build a UTF-8 PlatformFile from [text] with [name]. Bytes are populated
/// (rather than a real on-disk path) so the import flow's read-bytes path is
/// exercised without touching the filesystem.
PlatformFile platformFileFromText(String name, String text) {
  final bytes = Uint8List.fromList(utf8.encode(text));
  return PlatformFile(name: name, size: bytes.length, bytes: bytes);
}

/// Helper to build a one-chapter NovelSnapshot with a single root chapter
/// whose absolute path the export panel will read via readChapterRawText.
NovelSnapshot oneChapterNovelSnapshot({
  String title = '我的小说',
  String chapterTitle = '第1章',
  String chapterRelativePath = '正文/第1章.txt',
}) {
  final novelId = const NovelId('seeded-novel');
  final bodyId = const ContentId('seeded-body');
  final chapterId = const ContentId('seeded-chapter');
  return NovelSnapshot(
    rootPath: title,
    metadata: NovelMetadata(
      schemaVersion: 2,
      id: novelId,
      title: title,
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
          number: 1,
          role: ContentRole.normal,
        ),
      ],
    ),
  );
}

/// Resolve the absolute chapter path the export-access extension uses:
/// `p.posix.join(snapshot.rootPath, chapter.relativePath)`.
String absoluteChapterPath(NovelSnapshot snapshot, ContentNode chapter) =>
    p.posix.join(snapshot.rootPath, chapter.relativePath);

// ignore_for_file: unused_element
