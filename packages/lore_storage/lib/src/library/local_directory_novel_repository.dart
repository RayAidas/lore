import 'dart:io';

import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:path/path.dart' as p;

import 'internal/content_tree_scanner.dart';
import 'internal/library_entry_utils.dart';
import 'internal/library_path_resolver.dart';
import 'internal/library_paths.dart';
import 'internal/library_storage_io.dart';
import 'internal/novel_manifest_codec.dart';
import 'internal/pending_operation_journal.dart';
import 'internal/trash_internals.dart';

/// [NovelRepository] 端口适配器：list/load/create/register/renameNovel/
/// renameBody/deleteNovel。deleteNovel 会把小说目录移入回收站。
final class LocalDirectoryNovelRepository implements NovelRepository {
  LocalDirectoryNovelRepository({
    required this.idGenerator,
    required this.clock,
    required this.gateway,
    required this.paths,
    required this.resolver,
    required this.io,
    required this.entries,
    required this.novels,
    required this.scanner,
    required this.pending,
    required this.trash,
  });

  final IdGenerator idGenerator;
  final Clock clock;
  final LibraryFileOperationsGateway? gateway;
  final LibraryPaths paths;
  final LibraryPathResolver resolver;
  final LibraryStorageIo io;
  final LibraryEntryUtils entries;
  final NovelManifestCodec novels;
  final ContentTreeScanner scanner;
  final PendingOperationJournal pending;
  final TrashInternals trash;

  @override
  Future<List<NovelSnapshot>> listNovels(LibraryAccess access) async {
    final rootPath = await resolver.resolveRoot(access);
    final manifest = await io.readJsonObject(
      File(paths.manifestPath(rootPath)),
    );
    final list = <NovelSnapshot>[];
    for (final registration in novels.parseNovelRegistrations(
      manifest['novels'],
    )) {
      try {
        list.add(await novels.loadNovel(rootPath, registration));
      } on LibraryOperationException catch (error) {
        if (error.failure.code != LibraryFailureCode.notFound) {
          rethrow;
        }
      }
    }
    return list;
  }

  @override
  Future<NovelSnapshot> loadNovel(
    LibraryAccess access, {
    required NovelId novelId,
  }) async {
    final rootPath = await resolver.resolveRoot(access);
    return novels.loadNovel(
      rootPath,
      await novels.registrationFor(rootPath, novelId),
    );
  }

  @override
  Future<NovelStructureMutation> createNovel(
    LibraryAccess access, {
    required String title,
    ChapterFormat chapterFormat = ChapterFormat.markdown,
  }) async {
    final rootPath = await resolver.resolveRoot(access);
    final validTitle = entries.validateName(title);
    final novelRoot = p.join(rootPath, validTitle);
    if (await FileSystemEntity.type(novelRoot, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw io.alreadyExists(validTitle);
    }

    final now = clock.nowUtc();
    final metadata = NovelMetadata(
      schemaVersion: LibraryPaths.schemaVersion,
      revision: 0,
      id: NovelId(idGenerator.generate()),
      title: validTitle,
      description: '',
      coverPath: null,
      body: NovelBody(
        id: ContentId(idGenerator.generate()),
        relativePath: LibraryPaths.bodyDirectoryName,
      ),
      chapterFormat: chapterFormat,
      numberingMode: NumberingMode.continuous,
      createdAt: now,
      updatedAt: now,
    );
    final tree = ContentTree(
      schemaVersion: LibraryPaths.schemaVersion,
      novelId: metadata.id,
      revision: 0,
      nodes: const [],
    );
    await pending.writePending(
      rootPath,
      metadata.id,
      validTitle,
      operation: 'createNovel',
      targetPath: validTitle,
    );
    var created = false;
    try {
      await Directory(novelRoot).create();
      created = true;
      await Directory(
        p.join(novelRoot, LibraryPaths.metadataDirectoryName),
      ).create();
      await Directory(
        p.join(novelRoot, LibraryPaths.bodyDirectoryName),
      ).create();
      await io.writeJsonNew(
        File(paths.novelManifestPath(novelRoot)),
        novels.novelToJson(metadata),
      );
      await io.writeJsonNew(
        File(paths.contentManifestPath(novelRoot)),
        novels.contentToJson(tree),
      );
      await novels.registerNovel(rootPath, metadata.id, validTitle);
      await pending.clearPending(rootPath);
      final snapshot = NovelSnapshot(
        rootPath: validTitle,
        metadata: metadata,
        contentTree: tree,
      );
      return NovelStructureMutation(
        snapshot: snapshot,
        entry: entries.semanticEntry(
          name: validTitle,
          relativePath: validTitle,
          type: LibraryEntryType.directory,
          kind: LibraryEntrySemanticKind.novel,
          semanticId: metadata.id.value,
          novelId: metadata.id.value,
        ),
      );
    } catch (error) {
      if (created) {
        await io.deleteDirectorySafely(novelRoot, recursive: true);
      }
      await pending.clearPending(rootPath);
      if (error is FileSystemException) {
        throw LibraryOperationException(io.fileSystemFailure(error));
      }
      rethrow;
    }
  }

  @override
  Future<NovelStructureMutation> registerExistingNovel(
    LibraryAccess access, {
    required String relativePath,
  }) async {
    final rootPath = await resolver.resolveRoot(access);
    final novelRoot = await resolver.resolveExistingDirectory(
      rootPath,
      relativePath,
    );
    final normalizedPath = p.relative(novelRoot, from: rootPath);
    if (p.dirname(normalizedPath) != '.') {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.invalidLocation,
          message: '小说目录必须位于书库根级。',
        ),
      );
    }
    final novelFile = File(paths.novelManifestPath(novelRoot));
    NovelMetadata metadata;
    if (await novelFile.exists()) {
      metadata = novels.parseNovelMetadata(await io.readJsonObject(novelFile));
    } else {
      final bodyPath = p.join(novelRoot, LibraryPaths.bodyDirectoryName);
      final bodyType = await FileSystemEntity.type(
        bodyPath,
        followLinks: false,
      );
      if (bodyType == FileSystemEntityType.notFound) {
        await Directory(bodyPath).create();
      } else if (bodyType != FileSystemEntityType.directory) {
        throw const LibraryOperationException(
          LibraryFailure(
            code: LibraryFailureCode.invalidLocation,
            message: '“正文”已存在，但不是文件夹。',
          ),
        );
      }
      final now = clock.nowUtc();
      metadata = NovelMetadata(
        schemaVersion: LibraryPaths.schemaVersion,
        revision: 0,
        id: NovelId(idGenerator.generate()),
        title: p.basename(novelRoot),
        description: '',
        coverPath: null,
        body: NovelBody(
          id: ContentId(idGenerator.generate()),
          relativePath: LibraryPaths.bodyDirectoryName,
        ),
        chapterFormat: ChapterFormat.markdown,
        numberingMode: NumberingMode.continuous,
        createdAt: now,
        updatedAt: now,
      );
      await Directory(
        p.join(novelRoot, LibraryPaths.metadataDirectoryName),
      ).create();
      await io.writeJsonNew(novelFile, novels.novelToJson(metadata));
    }

    await pending.writePending(
      rootPath,
      metadata.id,
      normalizedPath,
      operation: 'registerNovel',
    );
    try {
      final contentFile = File(paths.contentManifestPath(novelRoot));
      final tree = await contentFile.exists()
          ? novels.parseContentTree(await io.readJsonObject(contentFile))
          : await scanner.scanContentTree(novelRoot, metadata, const []);
      if (tree.novelId != metadata.id) {
        throw const LibraryOperationException(
          LibraryFailure(
            code: LibraryFailureCode.metadataCorrupt,
            message: '小说与正文内容树的 ID 不一致。',
          ),
        );
      }
      if (!await contentFile.exists()) {
        await io.writeJsonNew(contentFile, novels.contentToJson(tree));
      }
      await novels.registerNovel(rootPath, metadata.id, normalizedPath);
      await pending.clearPending(rootPath);
      final snapshot = NovelSnapshot(
        rootPath: normalizedPath,
        metadata: metadata,
        contentTree: tree,
      );
      return NovelStructureMutation(
        snapshot: snapshot,
        entry: entries.semanticEntry(
          name: p.basename(novelRoot),
          relativePath: normalizedPath,
          type: LibraryEntryType.directory,
          kind: LibraryEntrySemanticKind.novel,
          semanticId: metadata.id.value,
          novelId: metadata.id.value,
        ),
      );
    } catch (error) {
      await pending.clearPending(rootPath);
      if (error is FileSystemException) {
        throw LibraryOperationException(io.fileSystemFailure(error));
      }
      rethrow;
    }
  }

  @override
  Future<NovelStructureMutation> renameNovel(
    LibraryAccess access, {
    required NovelId novelId,
    required String newName,
  }) async {
    final rootPath = await resolver.resolveRoot(access);
    final registration = await novels.registrationFor(rootPath, novelId);
    final snapshot = await novels.loadNovel(rootPath, registration);
    final validName = entries.validateName(newName);
    if (validName == snapshot.rootPath) {
      return NovelStructureMutation(
        snapshot: snapshot,
        entry: entries.semanticEntry(
          name: validName,
          relativePath: snapshot.rootPath,
          type: LibraryEntryType.directory,
          kind: LibraryEntrySemanticKind.novel,
          semanticId: novelId.value,
          novelId: novelId.value,
        ),
      );
    }
    final sourcePath = p.join(rootPath, snapshot.rootPath);
    final targetPath = p.join(rootPath, validName);
    if (await FileSystemEntity.type(targetPath, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw io.alreadyExists(validName);
    }
    await pending.writePending(
      rootPath,
      novelId,
      validName,
      operation: 'renameNovel',
      sourcePath: snapshot.rootPath,
      targetPath: validName,
    );
    await entries.renameEntity(
      access,
      gateway,
      rootPath,
      sourcePath,
      targetPath,
      FileSystemEntityType.directory,
    );
    final metadata = NovelMetadata(
      schemaVersion: snapshot.metadata.schemaVersion,
      revision: snapshot.metadata.revision + 1,
      id: snapshot.metadata.id,
      title: validName,
      description: snapshot.metadata.description,
      coverPath: snapshot.metadata.coverPath,
      body: snapshot.metadata.body,
      chapterFormat: snapshot.metadata.chapterFormat,
      numberingMode: snapshot.metadata.numberingMode,
      createdAt: snapshot.metadata.createdAt,
      updatedAt: clock.nowUtc(),
    );
    await io.writeJsonAtomic(
      File(paths.novelManifestPath(targetPath)),
      novels.novelToJson(metadata),
    );
    await novels.updateNovelRegistration(rootPath, novelId, validName);
    await pending.clearPending(rootPath);
    final updated = NovelSnapshot(
      rootPath: validName,
      metadata: metadata,
      contentTree: snapshot.contentTree,
    );
    return NovelStructureMutation(
      snapshot: updated,
      entry: entries.semanticEntry(
        name: validName,
        relativePath: validName,
        type: LibraryEntryType.directory,
        kind: LibraryEntrySemanticKind.novel,
        semanticId: novelId.value,
        novelId: novelId.value,
      ),
      pathChanges: [PathChange(oldPath: snapshot.rootPath, newPath: validName)],
    );
  }

  @override
  Future<NovelStructureMutation> renameBody(
    LibraryAccess access, {
    required NovelId novelId,
    required String newName,
  }) async {
    final rootPath = await resolver.resolveRoot(access);
    final snapshot = await novels.loadNovel(
      rootPath,
      await novels.registrationFor(rootPath, novelId),
    );
    final validName = entries.validateName(newName);
    final oldBody = snapshot.metadata.body.relativePath;
    if (validName == oldBody) {
      return NovelStructureMutation(
        snapshot: snapshot,
        entry: _bodyEntry(snapshot),
      );
    }
    final sourcePath = p.join(rootPath, snapshot.rootPath, oldBody);
    final targetPath = p.join(rootPath, snapshot.rootPath, validName);
    if (await FileSystemEntity.type(targetPath, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw io.alreadyExists(validName);
    }
    await pending.writePending(
      rootPath,
      novelId,
      snapshot.rootPath,
      operation: 'renameBody',
      sourcePath: p.join(snapshot.rootPath, oldBody),
      targetPath: p.join(snapshot.rootPath, validName),
    );
    await entries.renameEntity(
      access,
      gateway,
      rootPath,
      sourcePath,
      targetPath,
      FileSystemEntityType.directory,
    );
    final metadata = NovelMetadata(
      schemaVersion: snapshot.metadata.schemaVersion,
      revision: snapshot.metadata.revision + 1,
      id: snapshot.metadata.id,
      title: snapshot.metadata.title,
      description: snapshot.metadata.description,
      coverPath: snapshot.metadata.coverPath,
      body: NovelBody(id: snapshot.metadata.body.id, relativePath: validName),
      chapterFormat: snapshot.metadata.chapterFormat,
      numberingMode: snapshot.metadata.numberingMode,
      createdAt: snapshot.metadata.createdAt,
      updatedAt: clock.nowUtc(),
    );
    final nodes = snapshot.contentTree.nodes
        .map((node) {
          return node.copyWith(
            relativePath: p.join(
              validName,
              p.relative(node.relativePath, from: oldBody),
            ),
          );
        })
        .toList(growable: false);
    final tree = ContentTree(
      schemaVersion: snapshot.contentTree.schemaVersion,
      novelId: novelId,
      revision: snapshot.contentTree.revision + 1,
      nodes: nodes,
    );
    final novelRoot = p.join(rootPath, snapshot.rootPath);
    await io.writeJsonAtomic(
      File(paths.novelManifestPath(novelRoot)),
      novels.novelToJson(metadata),
    );
    await io.writeJsonAtomic(
      File(paths.contentManifestPath(novelRoot)),
      novels.contentToJson(tree),
    );
    await pending.clearPending(rootPath);
    final updated = NovelSnapshot(
      rootPath: snapshot.rootPath,
      metadata: metadata,
      contentTree: tree,
    );
    return NovelStructureMutation(
      snapshot: updated,
      entry: _bodyEntry(updated),
      pathChanges: [
        PathChange(
          oldPath: p.join(snapshot.rootPath, oldBody),
          newPath: p.join(snapshot.rootPath, validName),
        ),
      ],
    );
  }

  @override
  Future<DeletionResult> deleteNovel(
    LibraryAccess access, {
    required NovelId novelId,
  }) async {
    final rootPath = await resolver.resolveRoot(access);
    final registration = await novels.registrationFor(rootPath, novelId);
    final token = idGenerator.generate();

    await pending.writePending(
      rootPath,
      novelId,
      registration.relativePath,
      operation: 'trashNovel',
      sourcePath: registration.relativePath,
      targetPath: p.join(
        LibraryPaths.metadataDirectoryName,
        LibraryPaths.trashDirectoryName,
        token,
        registration.relativePath,
      ),
    );
    try {
      await trash.ensureTrashRoot(rootPath);
      await trash.moveIntoTrash(rootPath, token, registration.relativePath);
      await novels.removeNovelRegistration(rootPath, novelId);
      await trash.appendTrashManifest(
        rootPath,
        TrashItem(
          token: token,
          type: TrashItemType.novel,
          originalRelativePath: registration.relativePath,
          trashRelativePath: paths
              .resolveTrashTarget(rootPath, token, registration.relativePath)
              .substring(rootPath.length + 1),
          novelId: novelId.value,
          novelRootPath: registration.relativePath,
          deletedAt: clock.nowUtc(),
          restorable: true,
        ),
      );
      await pending.clearPending(rootPath);
    } on LibraryOperationException {
      await pending.clearPending(rootPath);
      rethrow;
    } on FileSystemException catch (error) {
      await pending.clearPending(rootPath);
      throw LibraryOperationException(io.fileSystemFailure(error));
    }

    return DeletionResult(
      trashToken: token,
      removedNodeIds: const [],
      pathChanges: [
        PathChange(
          oldPath: registration.relativePath,
          newPath: p.join(
            LibraryPaths.metadataDirectoryName,
            LibraryPaths.trashDirectoryName,
            token,
            registration.relativePath,
          ),
        ),
      ],
    );
  }

  LibraryEntry _bodyEntry(NovelSnapshot snapshot) {
    return entries.semanticEntry(
      name: snapshot.metadata.body.relativePath,
      relativePath: p.join(
        snapshot.rootPath,
        snapshot.metadata.body.relativePath,
      ),
      type: LibraryEntryType.directory,
      kind: LibraryEntrySemanticKind.body,
      semanticId: snapshot.metadata.body.id.value,
      novelId: snapshot.metadata.id.value,
    );
  }
}
