import 'dart:convert';

import 'package:lore_domain/lore_domain.dart';

import '../library/library_bootstrap.dart';
import '../ports/library_storage.dart';

/// AI 请求缓存的组合用例：经原始存储会话（字节 API）读写小说目录下的
/// `.cache` 文件。
///
/// 不能走文档仓储——它拒绝以 `.` 开头的文件名且过滤隐藏路径；而存储会话在
/// macOS 本地目录与 Android SAF 上签名一致且不过滤 dotfile，天然可移植。
/// 缓存文件不出现在侧栏目录树、不进版本历史、不算字数。
final class AiCacheService {
  const AiCacheService({required this.storageFactory});

  final LibraryStorageFactory storageFactory;

  static const cacheFileName = '.cache';
  static const _schemaVersion = 1;

  LogicalPath _cachePath(String novelRootPath) =>
      LogicalPath.parse(novelRootPath).child(cacheFileName);

  Future<AiCache> load(LibrarySession session, {required String novelRootPath}) async {
    final storage = await storageFactory.open(session.access);
    final path = _cachePath(novelRootPath);
    final entry = await storage.stat(path);
    if (entry == null) {
      return const AiCache.empty();
    }
    try {
      final bytes = await storage.readBytes(path);
      return _decode(utf8.decode(bytes)) ?? const AiCache.empty();
    } catch (_) {
      // 损坏/读取失败：回退空缓存，不阻塞面板。
      return const AiCache.empty();
    }
  }

  Future<void> save(
    LibrarySession session, {
    required String novelRootPath,
    required AiCache cache,
  }) async {
    final storage = await storageFactory.open(session.access);
    final path = _cachePath(novelRootPath);
    final bytes = utf8.encode(jsonEncode(_encode(cache)));
    final existing = await storage.stat(path);
    if (existing == null) {
      await storage.createFile(path, bytes);
      return;
    }
    final result = await storage.replaceFile(
      path,
      expectedRevision: existing.revision ?? '',
      bytes: bytes,
    );
    if (result is StorageReplaceConflict) {
      // 并发写入冲突：以最新 revision 重试一次。
      final fresh = await storage.stat(path);
      if (fresh != null) {
        await storage.replaceFile(
          path,
          expectedRevision: fresh.revision ?? '',
          bytes: bytes,
        );
      }
    }
  }

  Map<String, Object?> _encode(AiCache cache) {
    return {
      'schemaVersion': _schemaVersion,
      'entries': [
        for (final entry in cache.entries)
          {
            'ts': entry.timestampMillis,
            'kind': entry.kind.name,
            'prompt': entry.prompt,
            'context': entry.contextSummary,
            'output': entry.output,
          },
      ],
    };
  }

  AiCache? _decode(String encoded) {
    final value = jsonDecode(encoded);
    if (value is! Map<String, Object?>) {
      return null;
    }
    if (value['schemaVersion'] != _schemaVersion) {
      return null;
    }
    final rawEntries = value['entries'];
    if (rawEntries is! List<Object?>) {
      return null;
    }
    final entries = <AiCacheEntry>[];
    for (final item in rawEntries) {
      if (item is! Map<String, Object?>) {
        continue;
      }
      final ts = item['ts'];
      final kind = _kindFromName(item['kind']);
      final prompt = item['prompt'];
      final context = item['context'];
      final output = item['output'];
      if (ts is int &&
          kind != null &&
          prompt is String &&
          context is String &&
          output is String) {
        entries.add(
          AiCacheEntry(
            timestampMillis: ts,
            kind: kind,
            prompt: prompt,
            contextSummary: context,
            output: output,
          ),
        );
      }
    }
    return AiCache(entries);
  }

  AiCacheEntryKind? _kindFromName(Object? value) {
    return switch (value) {
      'action' => AiCacheEntryKind.action,
      'custom' => AiCacheEntryKind.custom,
      _ => null,
    };
  }
}
