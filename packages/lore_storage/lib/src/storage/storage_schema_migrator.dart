import 'dart:convert';
import 'dart:typed_data';

import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';

/// Migrates portable library metadata without relying on host filesystem paths.
final class StorageSchemaMigrator {
  const StorageSchemaMigrator({required this.idGenerator});

  final IdGenerator idGenerator;

  static final _manifest = LogicalPath.parse('.lore/library.json');
  static final _migrationRoot = LogicalPath.parse('.lore/recovery/migrations');

  Future<void> migrateIfNeeded(LibraryStorageSession storage) async {
    final library = await _readJson(storage, _manifest);
    final version = library['schemaVersion'];
    if (version == 2) {
      return;
    }
    if (version != 1) {
      throw LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.unsupportedSchema,
          message: '当前版本不支持书库格式版本 $version。',
        ),
      );
    }

    final registrations = _registrations(library['novels']);
    final backupRoot = _migrationRoot.child(idGenerator.generate());
    await _ensureDirectory(storage, backupRoot);
    final files = <(LogicalPath, LogicalPath)>[
      (_manifest, backupRoot.child('library.json')),
      for (final registration in registrations) ...[
        (
          registration.$2.child('.lore').child('novel.json'),
          backupRoot.child(registration.$1).child('novel.json'),
        ),
        (
          registration.$2.child('.lore').child('content.json'),
          backupRoot.child(registration.$1).child('content.json'),
        ),
      ],
    ];

    try {
      for (final file in files) {
        await _ensureDirectory(storage, file.$2.parent!);
        await storage.copy(file.$1, file.$2);
      }
      for (final registration in registrations) {
        final metadataRoot = registration.$2.child('.lore');
        final novelPath = metadataRoot.child('novel.json');
        final contentPath = metadataRoot.child('content.json');
        final novel = await _readJson(storage, novelPath);
        final content = await _readJson(storage, contentPath);
        _upgradeNovel(novel);
        _upgradeContent(content);
        await _replaceJson(storage, novelPath, novel);
        await _replaceJson(storage, contentPath, content);
      }
      _upgradeLibrary(library, registrations);
      await _replaceJson(storage, _manifest, library);
      await _validate(storage, registrations);
    } on Object {
      await _restore(storage, files);
      rethrow;
    }
  }

  List<(String, LogicalPath)> _registrations(Object? value) {
    if (value is! List<Object?>) {
      throw const FormatException('Invalid novel registrations.');
    }
    return value
        .map((item) {
          if (item is! Map<String, Object?> ||
              item['id'] is! String ||
              item['path'] is! String) {
            throw const FormatException('Invalid novel registration.');
          }
          return (
            item['id']! as String,
            _normalizePath(item['path']! as String),
          );
        })
        .toList(growable: false);
  }

  void _upgradeLibrary(
    Map<String, Object?> value,
    List<(String, LogicalPath)> registrations,
  ) {
    value['schemaVersion'] = 2;
    value['revision'] = 0;
    value['novels'] = registrations
        .map((item) => {'id': item.$1, 'path': item.$2.value})
        .toList(growable: false);
  }

  void _upgradeNovel(Map<String, Object?> value) {
    value['schemaVersion'] = 2;
    value['revision'] = 0;
    if (value['body'] case final Map<String, Object?> body) {
      body['path'] = _normalizePath(body['path'] as String).value;
    }
    if (value['cover'] case final String cover) {
      value['cover'] = _normalizePath(cover).value;
    }
  }

  void _upgradeContent(Map<String, Object?> value) {
    value['schemaVersion'] = 2;
    value.putIfAbsent('revision', () => 0);
    final nodes = value['nodes'];
    if (nodes is! List<Object?>) {
      throw const FormatException('Invalid content nodes.');
    }
    for (final item in nodes) {
      if (item is! Map<String, Object?> || item['path'] is! String) {
        throw const FormatException('Invalid content node.');
      }
      item['path'] = _normalizePath(item['path']! as String).value;
    }
  }

  LogicalPath _normalizePath(String value) {
    return LogicalPath.parse(value.replaceAll(r'\', '/'));
  }

  Future<void> _validate(
    LibraryStorageSession storage,
    List<(String, LogicalPath)> registrations,
  ) async {
    final library = await _readJson(storage, _manifest);
    if (library['schemaVersion'] != 2 || library['revision'] is! int) {
      throw const FormatException('Migrated library manifest is invalid.');
    }
    for (final registration in registrations) {
      final metadataRoot = registration.$2.child('.lore');
      final novel = await _readJson(storage, metadataRoot.child('novel.json'));
      final content = await _readJson(
        storage,
        metadataRoot.child('content.json'),
      );
      if (novel['schemaVersion'] != 2 ||
          novel['revision'] is! int ||
          content['schemaVersion'] != 2 ||
          content['revision'] is! int) {
        throw const FormatException('Migrated novel metadata is invalid.');
      }
    }
  }

  Future<void> _restore(
    LibraryStorageSession storage,
    List<(LogicalPath, LogicalPath)> files,
  ) async {
    for (final file in files.reversed) {
      final backup = await storage.stat(file.$2);
      final target = await storage.stat(file.$1);
      if (backup == null || target?.revision == null) {
        continue;
      }
      final result = await storage.replaceFile(
        file.$1,
        expectedRevision: target!.revision!,
        bytes: await storage.readBytes(file.$2),
      );
      if (result is StorageReplaceConflict) {
        throw const LibraryOperationException(
          LibraryFailure(
            code: LibraryFailureCode.externalModification,
            message: '迁移回滚期间元数据被外部修改，已保留迁移备份。',
          ),
        );
      }
    }
  }

  Future<void> _ensureDirectory(
    LibraryStorageSession storage,
    LogicalPath directory,
  ) async {
    if (directory.isRoot || await storage.stat(directory) != null) {
      return;
    }
    await _ensureDirectory(storage, directory.parent!);
    await storage.createDirectory(directory);
  }

  Future<Map<String, Object?>> _readJson(
    LibraryStorageSession storage,
    LogicalPath path,
  ) async {
    final value = jsonDecode(utf8.decode(await storage.readBytes(path)));
    if (value is! Map<String, Object?>) {
      throw const FormatException('Invalid metadata object.');
    }
    return value;
  }

  Future<void> _replaceJson(
    LibraryStorageSession storage,
    LogicalPath path,
    Map<String, Object?> value,
  ) async {
    final current = await storage.stat(path);
    if (current?.revision == null) {
      throw const FormatException('Metadata file is missing.');
    }
    final bytes = Uint8List.fromList(
      utf8.encode('${const JsonEncoder.withIndent('  ').convert(value)}\n'),
    );
    final result = await storage.replaceFile(
      path,
      expectedRevision: current!.revision!,
      bytes: bytes,
    );
    if (result is StorageReplaceConflict) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.externalModification,
          message: '迁移期间元数据被外部修改，请重新加载书库。',
        ),
      );
    }
  }
}
