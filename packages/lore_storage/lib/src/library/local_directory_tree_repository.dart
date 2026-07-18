import 'dart:convert';
import 'dart:io';

import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:path/path.dart' as p;

import 'internal/library_entry_utils.dart';
import 'internal/library_path_resolver.dart';
import 'internal/library_paths.dart';
import 'internal/library_storage_io.dart';
import 'internal/novel_manifest_codec.dart';
import 'internal/pending_operation_journal.dart';
import 'internal/trash_internals.dart';

/// [LibraryTreeRepository] 端口适配器：创建目录 / 创建文档 / 重命名 / 删除条目。
/// deleteEntry 会把条目移入回收站，依赖 [TrashInternals]。
///
/// 注意 [LibraryTreeRepository.listChildren] 与
/// [LibraryRepository.listChildren] 同名同签名；本适配器在此重新实现一份，
/// 与 `LocalDirectoryLibraryInspection.listChildren` 行为完全等价。
final class LocalDirectoryTreeRepository implements LibraryTreeRepository {
  LocalDirectoryTreeRepository({
    required this.idGenerator,
    required this.clock,
    required this.gateway,
    required this.paths,
    required this.resolver,
    required this.io,
    required this.entries,
    required this.novels,
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
  final PendingOperationJournal pending;
  final TrashInternals trash;

  @override
  Future<List<LibraryEntry>> listChildren(
    LibraryAccess access, {
    String relativePath = '',
  }) async {
    try {
      final rootPath = await resolver.resolveRoot(access);
      if (relativePath.isNotEmpty && paths.isHiddenPath(relativePath)) {
        throw const LibraryOperationException(
          LibraryFailure(
            code: LibraryFailureCode.invalidLocation,
            message: '不能访问书库内部目录。',
          ),
        );
      }
      final directoryPath =
          await resolver.resolveChildPath(rootPath, relativePath);
      final directory = Directory(directoryPath);
      if (!await directory.exists()) {
        throw const LibraryOperationException(
          LibraryFailure(
            code: LibraryFailureCode.notFound,
            message: '目录不存在或已被移动。',
          ),
        );
      }

      final list = <LibraryEntry>[];
      await for (final entity in directory.list(followLinks: false)) {
        final name = p.basename(entity.path);
        if (name.startsWith('.')) {
          continue;
        }
        final type = await FileSystemEntity.type(
          entity.path,
          followLinks: false,
        );
        if (type == FileSystemEntityType.link ||
            type == FileSystemEntityType.notFound) {
          continue;
        }
        list.add(
          LibraryEntry(
            name: name,
            relativePath: p.relative(entity.path, from: rootPath),
            type: entries.entryType(name, type),
          ),
        );
      }
      final annotated = await novels.annotateEntries(
        rootPath,
        relativePath,
        list,
        novels.loadNovel,
      );
      annotated.sort(entries.compareEntries);
      return annotated;
    } on LibraryOperationException {
      rethrow;
    } on FileSystemException catch (error) {
      throw LibraryOperationException(io.fileSystemFailure(error));
    }
  }

  @override
  Future<LibraryEntry> createDirectory(
    LibraryAccess access, {
    required String parentPath,
    required String name,
  }) async {
    try {
      final rootPath = await resolver.resolveRoot(access);
      final parent = await resolver.resolveExistingDirectory(
        rootPath,
        parentPath,
      );
      final validName = entries.validateName(name);
      final targetPath = p.join(parent, validName);
      if (await FileSystemEntity.type(targetPath, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw io.alreadyExists(validName);
      }
      await Directory(targetPath).create();
      return entries.entryForPath(
        rootPath,
        targetPath,
        FileSystemEntityType.directory,
      );
    } on LibraryOperationException {
      rethrow;
    } on FileSystemException catch (error) {
      throw LibraryOperationException(io.fileSystemFailure(error));
    }
  }

  @override
  Future<LibraryEntry> createDocument(
    LibraryAccess access, {
    required String parentPath,
    required String name,
    required DocumentFormat format,
    String initialText = '',
  }) async {
    String? createdPath;
    try {
      final rootPath = await resolver.resolveRoot(access);
      final parent = await resolver.resolveExistingDirectory(
        rootPath,
        parentPath,
      );
      final fileName = entries.documentFileName(name, format);
      final targetPath = p.join(parent, fileName);
      final file = File(targetPath);
      try {
        await file.create(exclusive: true);
        createdPath = targetPath;
      } on PathExistsException {
        throw io.alreadyExists(fileName);
      }
      await file.writeAsBytes(utf8.encode(initialText), flush: true);
      createdPath = null;
      return entries.entryForPath(
        rootPath,
        targetPath,
        FileSystemEntityType.file,
      );
    } on LibraryOperationException {
      rethrow;
    } on FileSystemException catch (error) {
      throw LibraryOperationException(io.fileSystemFailure(error));
    } finally {
      if (createdPath != null) {
        await io.deleteFileSafely(createdPath);
      }
    }
  }

  @override
  Future<LibraryEntry> renameEntry(
    LibraryAccess access, {
    required String relativePath,
    required String newName,
  }) async {
    try {
      final rootPath = await resolver.resolveRoot(access);
      final sourcePath = await resolver.resolveExistingEntity(
        rootPath,
        relativePath,
      );
      final sourceType = await FileSystemEntity.type(
        sourcePath,
        followLinks: false,
      );
      final currentName = p.basename(sourcePath);
      final validName = sourceType == FileSystemEntityType.file
          ? entries.renamedDocumentName(currentName, newName)
          : entries.validateName(newName);
      if (validName == currentName) {
        return entries.entryForPath(rootPath, sourcePath, sourceType);
      }

      final targetPath = p.join(p.dirname(sourcePath), validName);
      final targetType = await FileSystemEntity.type(
        targetPath,
        followLinks: false,
      );
      final caseOnlyRename =
          targetType != FileSystemEntityType.notFound &&
          p.equals(targetPath.toLowerCase(), sourcePath.toLowerCase());
      if (targetType != FileSystemEntityType.notFound && !caseOnlyRename) {
        throw io.alreadyExists(validName);
      }

      final renamedPath = caseOnlyRename
          ? await entries.renameChangingCase(
              access,
              gateway,
              idGenerator,
              rootPath,
              sourcePath,
              targetPath,
              sourceType,
            )
          : await entries.renameEntity(
              access,
              gateway,
              rootPath,
              sourcePath,
              targetPath,
              sourceType,
            );
      return entries.entryForPath(rootPath, renamedPath, sourceType);
    } on LibraryOperationException {
      rethrow;
    } on FileSystemException catch (error) {
      throw LibraryOperationException(io.fileSystemFailure(error));
    }
  }

  @override
  Future<DeletionResult> deleteEntry(
    LibraryAccess access, {
    required String relativePath,
  }) async {
    final rootPath = await resolver.resolveRoot(access);
    final entityPath = await resolver.resolveExistingEntity(
      rootPath,
      relativePath,
    );
    final normalized = p.relative(entityPath, from: rootPath);
    final token = idGenerator.generate();

    await pending.writePending(
      rootPath,
      const NovelId('00000000-0000-4000-8000-000000000000'),
      '',
      operation: 'trashEntry',
      sourcePath: normalized,
      targetPath: p.join(
        LibraryPaths.metadataDirectoryName,
        LibraryPaths.trashDirectoryName,
        token,
        normalized,
      ),
    );
    try {
      await trash.ensureTrashRoot(rootPath);
      await trash.moveIntoTrash(rootPath, token, normalized);
      await trash.appendTrashManifest(
        rootPath,
        TrashItem(
          token: token,
          type: TrashItemType.entry,
          originalRelativePath: normalized,
          trashRelativePath: paths
              .resolveTrashTarget(rootPath, token, normalized)
              .substring(rootPath.length + 1),
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
          oldPath: normalized,
          newPath: p.join(
            LibraryPaths.metadataDirectoryName,
            LibraryPaths.trashDirectoryName,
            token,
            normalized,
          ),
        ),
      ],
    );
  }
}
