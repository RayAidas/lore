import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';

import 'internal/content_tree_scanner.dart';
import 'internal/document_codec.dart';
import 'internal/library_entry_utils.dart';
import 'internal/library_path_resolver.dart';
import 'internal/library_paths.dart';
import 'internal/library_storage_io.dart';
import 'internal/novel_manifest_codec.dart';
import 'internal/pending_operation_journal.dart';
import 'internal/schema_migrator.dart';
import 'internal/trash_internals.dart';
import 'local_directory_content_tree_repository.dart';
import 'local_directory_document_repository.dart';
import 'local_directory_library_inspection.dart';
import 'local_directory_novel_repository.dart';
import 'local_directory_trash_repository.dart';
import 'local_directory_tree_repository.dart';

/// 本地目录书库实现：一个组合门面（Facade）。
///
/// 它对外暴露六个端口 ([LibraryRepository]、[LibraryTreeRepository]、
/// [DocumentRepository]、[NovelRepository]、[ContentTreeRepository]、
/// [TrashRepository])，对内把职责委派给 6 个适配器与一组共享内部助手。
///
/// 所有持久化逻辑、原子写、符号链接检查、BOM/CRLF 处理、macOS
/// 文件操作网关分支都已经在内部助手中实现；本类只负责构造依赖图与
/// 方法委派，确保单一职责、便于测试与未来替换实现。
final class LocalDirectoryLibraryRepository
    implements
        LibraryRepository,
        LibraryTreeRepository,
        DocumentRepository,
        NovelRepository,
        ContentTreeRepository,
        TrashRepository {
  LocalDirectoryLibraryRepository({
    required IdGenerator idGenerator,
    required Clock clock,
    this.fileOperationsGateway,
  }) {
    final paths = const LibraryPaths();
    final io = LibraryStorageIo(idGenerator);
    final resolver = LibraryPathResolver(paths);
    final entries = LibraryEntryUtils(paths: paths, io: io);
    final novels = NovelManifestCodec(
      paths: paths,
      io: io,
      clock: clock,
      resolver: resolver,
    );
    final scanner = ContentTreeScanner(idGenerator: idGenerator, paths: paths);
    final pending = PendingOperationJournal(
      paths: paths,
      io: io,
      novels: novels,
      scanner: scanner,
      clock: clock,
    );
    final migrator = LibrarySchemaMigrator(
      paths: paths,
      io: io,
      idGenerator: idGenerator,
    );
    final trash = TrashInternals(paths: paths, io: io, clock: clock);
    final codec = const DocumentCodec();

    _inspection = LocalDirectoryLibraryInspection(
      idGenerator: idGenerator,
      clock: clock,
      paths: paths,
      resolver: resolver,
      io: io,
      novels: novels,
      entries: entries,
      pending: pending,
      migrator: migrator,
    );
    _tree = LocalDirectoryTreeRepository(
      idGenerator: idGenerator,
      clock: clock,
      gateway: fileOperationsGateway,
      paths: paths,
      resolver: resolver,
      io: io,
      entries: entries,
      novels: novels,
      pending: pending,
      trash: trash,
    );
    _documents = LocalDirectoryDocumentRepository(
      idGenerator: idGenerator,
      gateway: fileOperationsGateway,
      paths: paths,
      resolver: resolver,
      io: io,
      codec: codec,
    );
    _novels = LocalDirectoryNovelRepository(
      idGenerator: idGenerator,
      clock: clock,
      gateway: fileOperationsGateway,
      paths: paths,
      resolver: resolver,
      io: io,
      entries: entries,
      novels: novels,
      scanner: scanner,
      pending: pending,
      trash: trash,
    );
    _contentTree = LocalDirectoryContentTreeRepository(
      idGenerator: idGenerator,
      clock: clock,
      gateway: fileOperationsGateway,
      paths: paths,
      resolver: resolver,
      io: io,
      entries: entries,
      novels: novels,
      scanner: scanner,
      pending: pending,
      trash: trash,
    );
    _trash = LocalDirectoryTrashRepository(
      paths: paths,
      resolver: resolver,
      io: io,
      novels: novels,
      scanner: scanner,
      pending: pending,
      trash: trash,
    );
  }

  /// macOS 平台下重命名 / 替换文档的安全网关；其它平台为 `null`，
  /// 适配器会回退到普通 dart:io 操作。
  final LibraryFileOperationsGateway? fileOperationsGateway;

  late final LocalDirectoryLibraryInspection _inspection;
  late final LocalDirectoryTreeRepository _tree;
  late final LocalDirectoryDocumentRepository _documents;
  late final LocalDirectoryNovelRepository _novels;
  late final LocalDirectoryContentTreeRepository _contentTree;
  late final LocalDirectoryTrashRepository _trash;

  // ---- LibraryRepository ------------------------------------------------

  @override
  Future<LibraryInspection> inspect(LibraryAccess access) =>
      _inspection.inspect(access);

  @override
  Future<LibraryMetadata> initialize(LibraryAccess access) =>
      _inspection.initialize(access);

  @override
  Future<List<LibraryEntry>> listChildren(
    LibraryAccess access, {
    String relativePath = '',
  }) => _inspection.listChildren(access, relativePath: relativePath);

  // ---- LibraryTreeRepository -------------------------------------------

  @override
  Future<LibraryEntry> createDirectory(
    LibraryAccess access, {
    required String parentPath,
    required String name,
  }) => _tree.createDirectory(access, parentPath: parentPath, name: name);

  @override
  Future<LibraryEntry> createDocument(
    LibraryAccess access, {
    required String parentPath,
    required String name,
    required DocumentFormat format,
    String initialText = '',
  }) => _tree.createDocument(
    access,
    parentPath: parentPath,
    name: name,
    format: format,
    initialText: initialText,
  );

  @override
  Future<LibraryEntry> renameEntry(
    LibraryAccess access, {
    required String relativePath,
    required String newName,
  }) => _tree.renameEntry(access, relativePath: relativePath, newName: newName);

  @override
  Future<DeletionResult> deleteEntry(
    LibraryAccess access, {
    required String relativePath,
  }) => _tree.deleteEntry(access, relativePath: relativePath);

  // ---- DocumentRepository ----------------------------------------------

  @override
  Future<DocumentSnapshot> readDocument(
    LibraryAccess access,
    DocumentRef ref,
  ) => _documents.readDocument(access, ref);

  @override
  Future<DocumentSaveResult> saveDocument(
    LibraryAccess access, {
    required DocumentSnapshot original,
    required String text,
  }) => _documents.saveDocument(access, original: original, text: text);

  @override
  Stream<DocumentChange> watchDocuments(LibraryAccess access) =>
      _documents.watchDocuments(access);

  // ---- NovelRepository --------------------------------------------------

  @override
  Future<List<NovelSnapshot>> listNovels(LibraryAccess access) =>
      _novels.listNovels(access);

  @override
  Future<NovelSnapshot> loadNovel(
    LibraryAccess access, {
    required NovelId novelId,
  }) => _novels.loadNovel(access, novelId: novelId);

  @override
  Future<NovelStructureMutation> createNovel(
    LibraryAccess access, {
    required String title,
    ChapterFormat chapterFormat = ChapterFormat.markdown,
  }) => _novels.createNovel(access, title: title, chapterFormat: chapterFormat);

  @override
  Future<NovelStructureMutation> registerExistingNovel(
    LibraryAccess access, {
    required String relativePath,
  }) => _novels.registerExistingNovel(access, relativePath: relativePath);

  @override
  Future<NovelStructureMutation> renameNovel(
    LibraryAccess access, {
    required NovelId novelId,
    required String newName,
  }) => _novels.renameNovel(access, novelId: novelId, newName: newName);

  @override
  Future<NovelStructureMutation> renameBody(
    LibraryAccess access, {
    required NovelId novelId,
    required String newName,
  }) => _novels.renameBody(access, novelId: novelId, newName: newName);

  @override
  Future<DeletionResult> deleteNovel(
    LibraryAccess access, {
    required NovelId novelId,
  }) => _novels.deleteNovel(access, novelId: novelId);

  // ---- ContentTreeRepository -------------------------------------------

  @override
  Future<NovelStructureMutation> createVolume(
    LibraryAccess access, {
    required NovelId novelId,
  }) => _contentTree.createVolume(access, novelId: novelId);

  @override
  Future<NovelStructureMutation> createChapter(
    LibraryAccess access, {
    required NovelId novelId,
    ContentId? volumeId,
  }) =>
      _contentTree.createChapter(access, novelId: novelId, volumeId: volumeId);

  @override
  Future<NovelStructureMutation> renameNode(
    LibraryAccess access, {
    required NovelId novelId,
    required ContentId nodeId,
    required String newName,
  }) => _contentTree.renameNode(
    access,
    novelId: novelId,
    nodeId: nodeId,
    newName: newName,
  );

  @override
  Future<NovelStructureMutation> moveChapter(
    LibraryAccess access, {
    required NovelId novelId,
    required ContentId chapterId,
    ContentId? volumeId,
  }) => _contentTree.moveChapter(
    access,
    novelId: novelId,
    chapterId: chapterId,
    volumeId: volumeId,
  );

  @override
  Future<NovelStructureMutation> reorderNode(
    LibraryAccess access, {
    required NovelId novelId,
    required ContentId nodeId,
    required int newIndex,
  }) => _contentTree.reorderNode(
    access,
    novelId: novelId,
    nodeId: nodeId,
    newIndex: newIndex,
  );

  @override
  Future<NovelReconciliationResult> reconcile(
    LibraryAccess access, {
    required NovelId novelId,
  }) => _contentTree.reconcile(access, novelId: novelId);

  @override
  Future<DeletionResult> deleteNode(
    LibraryAccess access, {
    required NovelId novelId,
    required ContentId nodeId,
  }) => _contentTree.deleteNode(access, novelId: novelId, nodeId: nodeId);

  // ---- TrashRepository --------------------------------------------------

  @override
  Future<List<TrashItem>> listItems(LibraryAccess access) =>
      _trash.listItems(access);

  @override
  Future<TrashItem> restore(
    LibraryAccess access, {
    required String trashToken,
    RestoreConflictStrategy strategy = RestoreConflictStrategy.rename,
  }) => _trash.restore(access, trashToken: trashToken, strategy: strategy);

  @override
  Future<void> purge(LibraryAccess access, {required String trashToken}) =>
      _trash.purge(access, trashToken: trashToken);

  @override
  Future<void> empty(LibraryAccess access) => _trash.empty(access);
}
