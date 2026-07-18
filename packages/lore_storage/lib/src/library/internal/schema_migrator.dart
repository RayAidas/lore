import 'dart:io';

import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:path/path.dart' as p;

import 'library_paths.dart';
import 'library_storage_io.dart';

final class LibrarySchemaMigrator {
  const LibrarySchemaMigrator({
    required this.paths,
    required this.io,
    required this.idGenerator,
  });

  final LibraryPaths paths;
  final LibraryStorageIo io;
  final IdGenerator idGenerator;

  Future<void> migrateIfNeeded(String rootPath) async {
    final libraryFile = File(paths.manifestPath(rootPath));
    final library = await io.readJsonObject(libraryFile);
    final version = library['schemaVersion'];
    if (version == LibraryPaths.schemaVersion) {
      await _pruneBackups(rootPath);
      return;
    }
    if (version != LibraryPaths.legacySchemaVersion) {
      throw LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.unsupportedSchema,
          message: '当前版本不支持书库格式版本 $version。',
        ),
      );
    }

    final registrations = _registrations(library['novels']);
    final migrationId = idGenerator.generate();
    final backupRoot = Directory(
      p.join(paths.migrationsRoot(rootPath), migrationId),
    );
    final journal = File(paths.migrationJournalPath(rootPath));
    await backupRoot.create(recursive: true);
    await journal.parent.create(recursive: true);
    await io.writeJsonAtomic(journal, {
      'schemaVersion': 1,
      'migration': 'v1-to-v2',
      'backupPath': p.relative(backupRoot.path, from: rootPath),
      'stage': 'backingUp',
    });

    try {
      await libraryFile.copy(p.join(backupRoot.path, 'library.json'));
      for (final registration in registrations) {
        final novelId = registration.$1;
        final novelPath = registration.$2;
        final sourceRoot = p.joinAll([
          rootPath,
          ...novelPath.value.split('/'),
          '.lore',
        ]);
        final targetRoot = Directory(p.join(backupRoot.path, novelId));
        await targetRoot.create(recursive: true);
        await File(
          p.join(sourceRoot, 'novel.json'),
        ).copy(p.join(targetRoot.path, 'novel.json'));
        await File(
          p.join(sourceRoot, 'content.json'),
        ).copy(p.join(targetRoot.path, 'content.json'));
      }
      await _updateJournal(journal, backupRoot, 'writing');

      for (final registration in registrations) {
        final novelRoot = p.joinAll([
          rootPath,
          ...registration.$2.value.split('/'),
          '.lore',
        ]);
        final novelFile = File(p.join(novelRoot, 'novel.json'));
        final contentFile = File(p.join(novelRoot, 'content.json'));
        final novel = await io.readJsonObject(novelFile);
        final content = await io.readJsonObject(contentFile);
        _upgradeNovel(novel);
        _upgradeContent(content);
        await io.writeJsonAtomic(novelFile, novel);
        await io.writeJsonAtomic(contentFile, content);
      }
      _upgradeLibrary(library);
      await io.writeJsonAtomic(libraryFile, library);
      await _updateJournal(journal, backupRoot, 'validating');
      await _validate(rootPath, registrations);
      await _updateJournal(journal, backupRoot, 'complete');
      await journal.delete();
      await _pruneBackups(rootPath);
    } catch (error) {
      await _restore(rootPath, backupRoot, registrations);
      if (await journal.exists()) {
        await journal.delete();
      }
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

  void _upgradeLibrary(Map<String, Object?> value) {
    value['schemaVersion'] = LibraryPaths.schemaVersion;
    value['revision'] = 0;
    value['novels'] = _registrations(value['novels'])
        .map((item) => {'id': item.$1, 'path': item.$2.value})
        .toList(growable: false);
  }

  void _upgradeNovel(Map<String, Object?> value) {
    value['schemaVersion'] = LibraryPaths.schemaVersion;
    value['revision'] = 0;
    if (value['body'] case final Map<String, Object?> body) {
      body['path'] = _normalizePath(body['path'] as String).value;
    }
    final cover = value['cover'];
    if (cover is String) {
      value['cover'] = _normalizePath(cover).value;
    }
  }

  void _upgradeContent(Map<String, Object?> value) {
    value['schemaVersion'] = LibraryPaths.schemaVersion;
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
    String rootPath,
    List<(String, LogicalPath)> registrations,
  ) async {
    final library = await io.readJsonObject(File(paths.manifestPath(rootPath)));
    if (library['schemaVersion'] != LibraryPaths.schemaVersion ||
        library['revision'] is! int) {
      throw const FormatException('Migrated library manifest is invalid.');
    }
    for (final registration in registrations) {
      final metadataRoot = p.joinAll([
        rootPath,
        ...registration.$2.value.split('/'),
        '.lore',
      ]);
      final novel = await io.readJsonObject(
        File(p.join(metadataRoot, 'novel.json')),
      );
      final content = await io.readJsonObject(
        File(p.join(metadataRoot, 'content.json')),
      );
      if (novel['schemaVersion'] != LibraryPaths.schemaVersion ||
          novel['revision'] is! int ||
          content['schemaVersion'] != LibraryPaths.schemaVersion ||
          content['revision'] is! int) {
        throw const FormatException('Migrated novel metadata is invalid.');
      }
    }
  }

  Future<void> _restore(
    String rootPath,
    Directory backupRoot,
    List<(String, LogicalPath)> registrations,
  ) async {
    final libraryBackup = File(p.join(backupRoot.path, 'library.json'));
    if (await libraryBackup.exists()) {
      await libraryBackup.copy(paths.manifestPath(rootPath));
    }
    for (final registration in registrations) {
      final targetRoot = p.joinAll([
        rootPath,
        ...registration.$2.value.split('/'),
        '.lore',
      ]);
      final sourceRoot = p.join(backupRoot.path, registration.$1);
      for (final name in ['novel.json', 'content.json']) {
        final source = File(p.join(sourceRoot, name));
        if (await source.exists()) {
          await source.copy(p.join(targetRoot, name));
        }
      }
    }
  }

  Future<void> _updateJournal(
    File journal,
    Directory backupRoot,
    String stage,
  ) {
    return io.writeJsonAtomic(journal, {
      'schemaVersion': 1,
      'migration': 'v1-to-v2',
      'backupPath': backupRoot.path,
      'stage': stage,
    });
  }

  Future<void> _pruneBackups(String rootPath) async {
    final root = Directory(paths.migrationsRoot(rootPath));
    if (!await root.exists()) {
      return;
    }
    final cutoff = DateTime.now().toUtc().subtract(const Duration(days: 7));
    await for (final entity in root.list(followLinks: false)) {
      if (entity is Directory &&
          (await entity.stat()).modified.toUtc().isBefore(cutoff)) {
        await entity.delete(recursive: true);
      }
    }
  }
}
