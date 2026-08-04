import 'dart:convert';
import 'dart:typed_data';

import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:test/test.dart';

/// 内存版存储会话：以路径为键存字节，revision 为内容派生值。
final class _MemoryStorage implements LibraryStorageSession {
  final Map<String, Uint8List> files = {};

  String _revisionOf(String path) => files.containsKey(path) ? 'rev:$path' : '';

  @override
  StorageCapabilities get capabilities => const StorageCapabilities(
    atomicReplace: true,
    move: true,
    rename: true,
    watch: false,
    caseSensitive: true,
  );

  @override
  Future<List<StorageEntry>> list(LogicalPath directory) async {
    final prefix = directory.isRoot ? '' : '${directory.value}/';
    return [
      for (final path in files.keys)
        if (path.startsWith(prefix) && !path.substring(prefix.length).contains('/'))
          StorageEntry(
            path: LogicalPath.parse(path),
            type: StorageEntryType.file,
            size: files[path]!.length,
            revision: _revisionOf(path),
          ),
    ];
  }

  @override
  Future<StorageEntry?> stat(LogicalPath path) async {
    final bytes = files[path.value];
    if (bytes == null) {
      return null;
    }
    return StorageEntry(
      path: path,
      type: StorageEntryType.file,
      size: bytes.length,
      revision: _revisionOf(path.value),
    );
  }

  @override
  Future<Uint8List> readBytes(LogicalPath path) async => files[path.value]!;

  @override
  Future<void> createDirectory(LogicalPath path) async {}

  @override
  Future<void> createFile(LogicalPath path, Uint8List bytes) async {
    if (files.containsKey(path.value)) {
      throw StateError('already exists: ${path.value}');
    }
    files[path.value] = bytes;
  }

  @override
  Future<StorageReplaceResult> replaceFile(
    LogicalPath path, {
    required String expectedRevision,
    required Uint8List bytes,
  }) async {
    final current = _revisionOf(path.value);
    if (current.isEmpty) {
      throw StateError('missing: ${path.value}');
    }
    if (expectedRevision != current) {
      return StorageReplaceConflict(current);
    }
    files[path.value] = bytes;
    return StorageReplaceSuccess(current);
  }

  @override
  Future<void> move(LogicalPath source, LogicalPath target) async {
    files[target.value] = files.remove(source.value)!;
  }

  @override
  Future<void> copy(LogicalPath source, LogicalPath target) async {
    files[target.value] = files[source.value]!;
  }

  @override
  Future<void> delete(LogicalPath path, {required bool recursive}) async {
    files.remove(path.value);
  }

  @override
  Stream<StorageChange> watch() => const Stream.empty();
}

final class _MemoryStorageFactory implements LibraryStorageFactory {
  _MemoryStorageFactory(this.storage);

  final LibraryStorageSession storage;

  @override
  Future<LibraryStorageSession> open(LibraryAccess access) async => storage;
}

void main() {
  const access = LibraryAccess(
    token: '/tmp/library',
    displayPath: '/tmp/library',
    isPending: false,
  );
  final metadata = LibraryMetadata(
    schemaVersion: 1,
    id: const LibraryId('11111111-1111-4111-8111-111111111111'),
    createdAt: DateTime.utc(2026, 8, 4),
    updatedAt: DateTime.utc(2026, 8, 4),
  );
  final session = LibrarySession(access: access, metadata: metadata);

  const novelRoot = '我的小说';

  late _MemoryStorage storage;
  late AiCacheService service;

  setUp(() {
    storage = _MemoryStorage();
    service = AiCacheService(storageFactory: _MemoryStorageFactory(storage));
  });

  const entry = AiCacheEntry(
    timestampMillis: 1000,
    kind: AiCacheEntryKind.action,
    prompt: 'polish',
    contextSummary: '当前章节正文 · 100 字',
    output: '润色结果',
  );

  test('load returns empty cache when no file exists', () async {
    final cache = await service.load(session, novelRootPath: novelRoot);
    expect(cache.entries, isEmpty);
  });

  test('append + save then load round-trips', () async {
    await service.save(
      session,
      novelRootPath: novelRoot,
      cache: const AiCache.empty().append(entry),
    );

    final loaded = await service.load(session, novelRootPath: novelRoot);
    expect(loaded.entries, hasLength(1));
    expect(loaded.entries.single.prompt, 'polish');
    expect(loaded.entries.single.output, '润色结果');
    expect(loaded.entries.single.kind, AiCacheEntryKind.action);
  });

  test('save on an existing file replaces via CAS', () async {
    await service.save(
      session,
      novelRootPath: novelRoot,
      cache: const AiCache.empty().append(entry),
    );
    final second = const AiCacheEntry(
      timestampMillis: 2000,
      kind: AiCacheEntryKind.custom,
      prompt: '改成更口语',
      contextSummary: '选中文字 · 20 字',
      output: '结果',
    );
    await service.save(
      session,
      novelRootPath: novelRoot,
      cache: const AiCache.empty().append(entry).append(second),
    );

    final loaded = await service.load(session, novelRootPath: novelRoot);
    expect(loaded.entries, hasLength(2));
    expect(loaded.entries.last.output, '结果');
  });

  test('load falls back to empty on corrupted json', () async {
    storage.files['$novelRoot/.cache'] = Uint8List.fromList(
      utf8.encode('not-json'),
    );
    expect(
      (await service.load(session, novelRootPath: novelRoot)).entries,
      isEmpty,
    );
  });

  test('load falls back to empty on a wrong schema version', () async {
    storage.files['$novelRoot/.cache'] = Uint8List.fromList(
      utf8.encode(jsonEncode({'schemaVersion': 99, 'entries': []})),
    );
    expect(
      (await service.load(session, novelRootPath: novelRoot)).entries,
      isEmpty,
    );
  });
}
