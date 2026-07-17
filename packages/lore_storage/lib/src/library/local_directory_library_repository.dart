import 'dart:convert';
import 'dart:io';

import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:path/path.dart' as p;

final class LocalDirectoryLibraryRepository implements LibraryRepository {
  const LocalDirectoryLibraryRepository({
    required this._idGenerator,
    required this._clock,
  });

  static const _schemaVersion = 1;
  static const _metadataDirectoryName = '.lore';
  static const _manifestFileName = 'library.json';

  final IdGenerator _idGenerator;
  final Clock _clock;

  @override
  Future<LibraryInspection> inspect(LibraryAccess access) async {
    try {
      final rootPath = await _resolveRoot(access);
      final metadataDirectoryPath = p.join(rootPath, _metadataDirectoryName);
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

      final manifest = File(_manifestPath(rootPath));
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

      final value = jsonDecode(await manifest.readAsString());
      if (value is! Map<String, Object?>) {
        return _corrupt('书库元数据不是有效的 JSON 对象。');
      }

      final schemaVersion = value['schemaVersion'];
      if (schemaVersion is! int) {
        return _corrupt('书库元数据缺少 schemaVersion。');
      }
      if (schemaVersion != _schemaVersion) {
        return LibraryInspectionFailure(
          LibraryFailure(
            code: LibraryFailureCode.unsupportedSchema,
            message: '当前版本不支持书库格式版本 $schemaVersion。',
          ),
        );
      }

      final libraryId = value['libraryId'];
      final createdAt = value['createdAt'];
      final updatedAt = value['updatedAt'];
      if (libraryId is! String || !_isUuid(libraryId)) {
        return _corrupt('书库 ID 无效。');
      }
      if (createdAt is! String || updatedAt is! String) {
        return _corrupt('书库时间信息无效。');
      }
      if (value['novels'] is! List<Object?> ||
          value['templates'] is! List<Object?>) {
        return _corrupt('书库注册信息无效。');
      }

      final created = DateTime.tryParse(createdAt);
      final updated = DateTime.tryParse(updatedAt);
      if (created == null || updated == null) {
        return _corrupt('书库时间信息无法解析。');
      }

      return LibraryInspectionReady(
        LibraryMetadata(
          schemaVersion: schemaVersion,
          id: LibraryId(libraryId),
          createdAt: created.toUtc(),
          updatedAt: updated.toUtc(),
        ),
      );
    } on FormatException {
      return _corrupt('书库元数据 JSON 已损坏。');
    } on FileSystemException catch (error) {
      return LibraryInspectionFailure(_fileSystemFailure(error));
    } on LibraryOperationException catch (error) {
      return LibraryInspectionFailure(error.failure);
    }
  }

  @override
  Future<LibraryMetadata> initialize(LibraryAccess access) async {
    String? createdManifestPath;
    try {
      final rootPath = await _resolveRoot(access);
      final existing = await inspect(access);
      if (existing case LibraryInspectionReady(:final metadata)) {
        return metadata;
      }
      if (existing case LibraryInspectionFailure(:final failure)) {
        throw LibraryOperationException(failure);
      }

      final metadataDirectory = Directory(
        p.join(rootPath, _metadataDirectoryName),
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

      final now = _clock.nowUtc();
      final metadata = LibraryMetadata(
        schemaVersion: _schemaVersion,
        id: LibraryId(_idGenerator.generate()),
        createdAt: now,
        updatedAt: now,
      );
      final manifestPath = _manifestPath(rootPath);
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
        '${const JsonEncoder.withIndent('  ').convert(_toJson(metadata))}\n',
        flush: true,
      );
      createdManifestPath = null;
      return metadata;
    } on LibraryOperationException {
      rethrow;
    } on FileSystemException catch (error) {
      throw LibraryOperationException(_fileSystemFailure(error));
    } finally {
      if (createdManifestPath != null) {
        await _deleteFileSafely(createdManifestPath);
      }
    }
  }

  @override
  Future<List<LibraryEntry>> listChildren(
    LibraryAccess access, {
    String relativePath = '',
  }) async {
    try {
      final rootPath = await _resolveRoot(access);
      final directoryPath = await _resolveChildPath(rootPath, relativePath);
      final directory = Directory(directoryPath);
      if (!await directory.exists()) {
        throw const LibraryOperationException(
          LibraryFailure(
            code: LibraryFailureCode.notFound,
            message: '目录不存在或已被移动。',
          ),
        );
      }

      final entries = <LibraryEntry>[];
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
        entries.add(
          LibraryEntry(
            name: name,
            relativePath: p.relative(entity.path, from: rootPath),
            type: _entryType(name, type),
          ),
        );
      }
      entries.sort(_compareEntries);
      return entries;
    } on LibraryOperationException {
      rethrow;
    } on FileSystemException catch (error) {
      throw LibraryOperationException(_fileSystemFailure(error));
    }
  }

  Future<String> _resolveRoot(LibraryAccess access) async {
    final directory = Directory(p.normalize(p.absolute(access.token)));
    if (!await directory.exists()) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.notFound,
          message: '书库目录不存在或已被移动。',
        ),
      );
    }
    final rootPath = p.normalize(await directory.resolveSymbolicLinks());
    if (rootPath == p.rootPrefix(rootPath)) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.invalidLocation,
          message: '不能将文件系统根目录设为书库。',
        ),
      );
    }
    return rootPath;
  }

  Future<String> _resolveChildPath(String rootPath, String relativePath) async {
    if (p.isAbsolute(relativePath)) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.invalidLocation,
          message: '目录路径超出了书库范围。',
        ),
      );
    }
    final candidate = p.normalize(p.join(rootPath, relativePath));
    if (candidate != rootPath && !p.isWithin(rootPath, candidate)) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.invalidLocation,
          message: '目录路径超出了书库范围。',
        ),
      );
    }

    final candidateType = await FileSystemEntity.type(
      candidate,
      followLinks: false,
    );
    if (candidateType == FileSystemEntityType.link) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.invalidLocation,
          message: '目录路径不能包含符号链接。',
        ),
      );
    }
    if (candidateType == FileSystemEntityType.notFound) {
      return candidate;
    }

    final resolvedCandidate = p.normalize(
      await Directory(candidate).resolveSymbolicLinks(),
    );
    if (resolvedCandidate != rootPath &&
        !p.isWithin(rootPath, resolvedCandidate)) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.invalidLocation,
          message: '目录路径超出了书库范围。',
        ),
      );
    }
    return resolvedCandidate;
  }

  String _manifestPath(String rootPath) {
    return p.join(rootPath, _metadataDirectoryName, _manifestFileName);
  }

  Map<String, Object?> _toJson(LibraryMetadata metadata) {
    return {
      'schemaVersion': metadata.schemaVersion,
      'libraryId': metadata.id.value,
      'createdAt': metadata.createdAt.toUtc().toIso8601String(),
      'updatedAt': metadata.updatedAt.toUtc().toIso8601String(),
      'novels': <Object?>[],
      'templates': <Object?>[],
    };
  }

  LibraryInspectionFailure _corrupt(String message) {
    return LibraryInspectionFailure(
      LibraryFailure(
        code: LibraryFailureCode.metadataCorrupt,
        message: message,
      ),
    );
  }

  LibraryFailure _fileSystemFailure(FileSystemException error) {
    final errorCode = error.osError?.errorCode;
    final permissionDenied = errorCode == 1 || errorCode == 13;
    return LibraryFailure(
      code: permissionDenied
          ? LibraryFailureCode.notWritable
          : LibraryFailureCode.io,
      message: permissionDenied ? '没有权限写入书库目录。' : '书库文件操作失败。',
    );
  }

  bool _isUuid(String value) {
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(value);
  }

  LibraryEntryType _entryType(String name, FileSystemEntityType type) {
    if (type == FileSystemEntityType.directory) {
      return LibraryEntryType.directory;
    }
    return switch (p.extension(name).toLowerCase()) {
      '.txt' => LibraryEntryType.textFile,
      '.md' => LibraryEntryType.markdownFile,
      _ => LibraryEntryType.otherFile,
    };
  }

  int _compareEntries(LibraryEntry left, LibraryEntry right) {
    if (left.isDirectory != right.isDirectory) {
      return left.isDirectory ? -1 : 1;
    }
    return left.name.toLowerCase().compareTo(right.name.toLowerCase());
  }

  Future<void> _deleteFileSafely(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException catch (_) {
      return;
    }
  }
}
