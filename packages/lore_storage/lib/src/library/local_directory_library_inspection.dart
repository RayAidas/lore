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
import 'internal/schema_migrator.dart';

/// [LibraryRepository] 端口适配器：书库自检、初始化与根级目录列举。
///
/// 这是 [LocalDirectoryLibraryRepository] 拆分后负责 LibraryRepository 端口的
/// 实现；逻辑与原实现等价。
final class LocalDirectoryLibraryInspection implements LibraryRepository {
  LocalDirectoryLibraryInspection({
    required this.idGenerator,
    required this.clock,
    required this.paths,
    required this.resolver,
    required this.io,
    required this.novels,
    required this.entries,
    required this.pending,
    required this.migrator,
  });

  final IdGenerator idGenerator;
  final Clock clock;
  final LibraryPaths paths;
  final LibraryPathResolver resolver;
  final LibraryStorageIo io;
  final NovelManifestCodec novels;
  final LibraryEntryUtils entries;
  final PendingOperationJournal pending;
  final LibrarySchemaMigrator migrator;

  @override
  Future<LibraryInspection> inspect(LibraryAccess access) async {
    try {
      final rootPath = await resolver.resolveRoot(access);
      final metadataDirectoryPath = p.join(
        rootPath,
        LibraryPaths.metadataDirectoryName,
      );
      final metadataType = await FileSystemEntity.type(
        metadataDirectoryPath,
        followLinks: false,
      );
      if (metadataType == FileSystemEntityType.notFound) {
        return const LibraryInspectionNeedsInitialization();
      }
      if (metadataType != FileSystemEntityType.directory) {
        return const LibraryInspectionFailure(
          LibraryFailure(
            code: LibraryFailureCode.invalidLocation,
            message: '.lore 已存在，但不是普通文件夹。',
          ),
        );
      }

      final manifest = File(paths.manifestPath(rootPath));
      final manifestType = await FileSystemEntity.type(
        manifest.path,
        followLinks: false,
      );
      if (manifestType == FileSystemEntityType.notFound) {
        return const LibraryInspectionNeedsInitialization();
      }
      if (manifestType != FileSystemEntityType.file) {
        return const LibraryInspectionFailure(
          LibraryFailure(
            code: LibraryFailureCode.invalidLocation,
            message: '书库元数据必须是普通文件。',
          ),
        );
      }

      await migrator.migrateIfNeeded(rootPath);

      var value = jsonDecode(await manifest.readAsString());
      if (value is! Map<String, Object?>) {
        return entries.corrupt('书库元数据不是有效的 JSON 对象。');
      }

      final schemaVersion = value['schemaVersion'];
      if (schemaVersion is! int) {
        return entries.corrupt('书库元数据缺少 schemaVersion。');
      }
      if (schemaVersion != LibraryPaths.schemaVersion) {
        return LibraryInspectionFailure(
          LibraryFailure(
            code: LibraryFailureCode.unsupportedSchema,
            message: '当前版本不支持书库格式版本 $schemaVersion。',
          ),
        );
      }

      final libraryId = value['libraryId'];
      final revision = value['revision'];
      final createdAt = value['createdAt'];
      final updatedAt = value['updatedAt'];
      if (libraryId is! String || !io.isUuid(libraryId) || revision is! int) {
        return entries.corrupt('书库 ID 无效。');
      }
      if (createdAt is! String || updatedAt is! String) {
        return entries.corrupt('书库时间信息无效。');
      }
      if (value['novels'] is! List<Object?> ||
          value['templates'] is! List<Object?>) {
        return entries.corrupt('书库注册信息无效。');
      }

      final created = DateTime.tryParse(createdAt);
      final updated = DateTime.tryParse(updatedAt);
      if (created == null || updated == null) {
        return entries.corrupt('书库时间信息无法解析。');
      }

      await pending.recoverPending(rootPath);
      value = jsonDecode(await manifest.readAsString());
      if (value is! Map<String, Object?>) {
        return entries.corrupt('恢复后的书库元数据无效。');
      }

      final novelRegistrations = novels.parseNovelRegistrations(
        value['novels'],
      );
      return LibraryInspectionReady(
        LibraryMetadata(
          schemaVersion: schemaVersion,
          revision: revision,
          id: LibraryId(libraryId),
          createdAt: created.toUtc(),
          updatedAt: updated.toUtc(),
          novels: novelRegistrations,
        ),
      );
    } on FormatException {
      return entries.corrupt('书库元数据 JSON 已损坏。');
    } on FileSystemException catch (error) {
      return LibraryInspectionFailure(io.fileSystemFailure(error));
    } on LibraryOperationException catch (error) {
      return LibraryInspectionFailure(error.failure);
    }
  }

  @override
  Future<LibraryMetadata> initialize(LibraryAccess access) async {
    String? createdManifestPath;
    try {
      final rootPath = await resolver.resolveRoot(access);
      final existing = await inspect(access);
      if (existing case LibraryInspectionReady(:final metadata)) {
        return metadata;
      }
      if (existing case LibraryInspectionFailure(:final failure)) {
        throw LibraryOperationException(failure);
      }

      final metadataDirectory = Directory(
        p.join(rootPath, LibraryPaths.metadataDirectoryName),
      );
      final metadataType = await FileSystemEntity.type(
        metadataDirectory.path,
        followLinks: false,
      );
      if (metadataType != FileSystemEntityType.notFound &&
          metadataType != FileSystemEntityType.directory) {
        throw const LibraryOperationException(
          LibraryFailure(
            code: LibraryFailureCode.notWritable,
            message: '.lore 已存在，但不是文件夹。',
          ),
        );
      }
      await metadataDirectory.create(recursive: true);

      final now = clock.nowUtc();
      final metadata = LibraryMetadata(
        schemaVersion: LibraryPaths.schemaVersion,
        revision: 0,
        id: LibraryId(idGenerator.generate()),
        createdAt: now,
        updatedAt: now,
        novels: const [],
      );
      final manifestPath = paths.manifestPath(rootPath);
      final manifest = File(manifestPath);
      try {
        await manifest.create(exclusive: true);
        createdManifestPath = manifestPath;
      } on PathExistsException {
        throw const LibraryOperationException(
          LibraryFailure(
            code: LibraryFailureCode.metadataCorrupt,
            message: '初始化期间检测到已有书库元数据，未执行覆盖。',
          ),
        );
      }
      await manifest.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(novels.toJson(metadata))}\n',
        flush: true,
      );
      createdManifestPath = null;
      return metadata;
    } on LibraryOperationException {
      rethrow;
    } on FileSystemException catch (error) {
      throw LibraryOperationException(io.fileSystemFailure(error));
    } finally {
      if (createdManifestPath != null) {
        await io.deleteFileSafely(createdManifestPath);
      }
    }
  }

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
      final directoryPath = await resolver.resolveChildPath(
        rootPath,
        relativePath,
      );
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
}
