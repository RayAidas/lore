part of '../storage_backed_library_repository.dart';

/// 历史快照存储支持：目录命名、gzip 编解码、内容哈希、manifest 读写与快照
/// 条目 JSON 编解码。manifest 采用 read-modify-write + 乐观锁重试，与
/// highlights.json 同构。
///
/// 目录结构：
/// ```
/// .lore/history/
///   <dirName>/            # 章节用 nodeId；普通文件用 relativePath 的 sha1
///     manifest.json       # 该文档所有快照元信息
///     snapshots/
///       20260722T143000Z_a1b2c3.txt.gz
/// ```
mixin _StorageBackedHistorySupport on _StorageBackedLibrarySupport {
  /// 历史目录名：章节用 [DocumentIdentity.nodeId]（稳定，移动不断链）；普通文件
  /// 用 relativePath 的 sha1（路径含 `/` 不能直接做目录名，文件移动后哈希变化，
  /// 历史断链——已知限制）。
  String _historyDirName(DocumentIdentity doc) {
    final nodeId = doc.nodeId;
    if (nodeId != null) return nodeId;
    return sha1.convert(utf8.encode(doc.relativePath)).toString();
  }

  LogicalPath _historyDocRoot(DocumentIdentity doc) =>
      _historyRoot.child(_historyDirName(doc));

  LogicalPath _historyManifestPath(DocumentIdentity doc) =>
      _historyDocRoot(doc).child('manifest.json');

  LogicalPath _historySnapshotsDir(DocumentIdentity doc) =>
      _historyDocRoot(doc).child('snapshots');

  String _snapshotFileName(DateTime createdAtUtc, String snapshotId) {
    // 用完整 snapshotId（全局唯一）作文件名主体，避免「时间戳 + 短哈希」在
    // 时钟回拨或短哈希碰撞时撞名——createFile 是 exclusive，撞名会抛
    // alreadyExists 并被上层吞掉，导致快照静默丢失。
    return '${_compactUtc(createdAtUtc)}_$snapshotId.txt.gz';
  }

  String _compactUtc(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    String four(int n) => n.toString().padLeft(4, '0');
    return '${four(t.year)}${two(t.month)}${two(t.day)}T'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}Z';
  }

  String _contentHashOf(String text) =>
      sha256.convert(utf8.encode(text)).toString();

  Uint8List _gzipEncode(String text) =>
      Uint8List.fromList(gzip.encode(utf8.encode(text)));

  String _gzipDecode(Uint8List bytes) => utf8.decode(gzip.decode(bytes));

  Future<_HistoryManifest?> _readHistoryManifest(
    LibraryStorageSession storage,
    DocumentIdentity doc,
  ) async {
    final path = _historyManifestPath(doc);
    try {
      if (await storage.stat(path) == null) return null;
      return _historyManifestFromJson(await _readJson(storage, path));
    } catch (error) {
      if (_isExpectedHistoryReadFailure(error)) {
        // manifest 缺失/损坏/不可读（旧版残留、写入中断留下空文件、权限、瞬态
        // IO 等）：历史是 best-effort，视为无 manifest——list 返回空，record 以
        // replace 覆盖重建。打日志便于排查，不静默吞掉。
        stderr.writeln('[lore-history] manifest 读取失败 $path: $error');
        return null;
      }
      rethrow;
    }
  }

  /// 读取 manifest 时「预期内」的失败：解析 / IO / 路径类异常。这些降级为空态；
  /// 其余（多为编程错误）向上抛出，避免被静默吞掉。
  bool _isExpectedHistoryReadFailure(Object error) =>
      error is FormatException ||
      error is ArgumentError ||
      error is FileSystemException ||
      error is LibraryOperationException;

  Future<void> _writeHistoryManifest(
    LibraryStorageSession storage,
    DocumentIdentity doc,
    _HistoryManifest manifest, {
    required bool create,
  }) async {
    // 递归建立 snapshots 目录（同时建立 manifest 父目录 _historyDocRoot）。
    await _ensurePortableDirectory(storage, _historySnapshotsDir(doc));
    final path = _historyManifestPath(doc);
    final value = _historyManifestToJson(manifest);
    if (create) {
      // 首次写入走原子化路径，避免崩溃留下 0 字节 manifest。
      await _writeNewJsonAtomic(storage, path, value);
    } else {
      await _replaceJson(storage, path, value);
    }
  }

  /// read-modify-write + 乐观锁重试，覆盖 record/delete/prune 写入。
  /// [mutate] 直接修改 manifest 内存结构，返回 false 表示无需写回。并发改写
  /// （externalModification）或首次写竞态（alreadyExists）时重读重试，最多
  /// [_historyWriteAttempts] 次。返回写回后的 manifest（或去重时未变更的原 manifest）。
  Future<_HistoryManifest> _modifyHistoryManifest(
    LibraryAccess access,
    DocumentIdentity doc, {
    required bool Function(_HistoryManifest manifest) mutate,
  }) async {
    var attempt = 0;
    while (true) {
      attempt += 1;
      final storage = await storageFactory.open(access);
      final manifestPath = _historyManifestPath(doc);
      // 以「文件是否存在」而非「是否解析成功」决定 create/replace：manifest 损坏
      // 时 _readHistoryManifest 返回 null 但文件仍在——此时必须 replace 覆盖，
      // 否则 exclusive create 会反复 alreadyExists，record 永远写不进去。
      bool fileExists;
      try {
        fileExists = await storage.stat(manifestPath) != null;
      } catch (_) {
        // stat 自身抛错（IO 等）时按「不存在」处理：走 create，由 alreadyExists
        // 重试机制兜底，不让 record 在此处直接失败。
        fileExists = false;
      }
      final existing = await _readHistoryManifest(storage, doc);
      final manifest = existing ?? _HistoryManifest.empty(doc);
      if (!mutate(manifest)) return manifest;
      try {
        await _writeHistoryManifest(
          storage,
          doc,
          manifest,
          create: !fileExists,
        );
        return manifest;
      } on LibraryOperationException catch (error) {
        final retriable =
            error.failure.code == LibraryFailureCode.externalModification ||
            error.failure.code == LibraryFailureCode.alreadyExists;
        if (!retriable || attempt >= _historyWriteAttempts) rethrow;
      }
    }
  }

  static const _historyWriteAttempts = 3;
}

/// 单文档的历史 manifest（内存镜像，读写均经过它）。
final class _HistoryManifest {
  _HistoryManifest({
    required this.historyKey,
    required this.relativePath,
    required this.format,
    required this.entries,
  });

  factory _HistoryManifest.empty(DocumentIdentity doc) => _HistoryManifest(
    historyKey: doc.logicalKey,
    relativePath: doc.relativePath,
    format: doc.format.name,
    entries: <_HistoryEntry>[],
  );

  String historyKey;
  String relativePath;
  String format;
  final List<_HistoryEntry> entries;

  /// 最新条目（按 createdAt 最大），作为哈希去重的比较基准。
  _HistoryEntry? get latest {
    _HistoryEntry? best;
    for (final entry in entries) {
      if (best == null ||
          entry.snapshot.createdAt.compareTo(best.snapshot.createdAt) > 0) {
        best = entry;
      }
    }
    return best;
  }

  _HistoryEntry? entryById(String snapshotId) {
    for (final entry in entries) {
      if (entry.snapshot.id == snapshotId) return entry;
    }
    return null;
  }

  List<HistorySnapshot> get snapshots =>
      entries.map((entry) => entry.snapshot).toList(growable: false);
}

/// manifest 中的一条快照记录：领域元信息 + 存储细节（gzip 文件名、压缩字节数）。
final class _HistoryEntry {
  const _HistoryEntry({
    required this.snapshot,
    required this.file,
    required this.byteSize,
  });

  final HistorySnapshot snapshot;

  /// 相对 snapshots 目录的文件名。
  final String file;

  /// gzip 压缩后字节数，用于占用估算。
  final int byteSize;
}

_HistoryManifest _historyManifestFromJson(Map<String, Object?> value) {
  if (value['schemaVersion'] != 1 ||
      value['historyKey'] is! String ||
      value['relativePath'] is! String ||
      value['format'] is! String ||
      value['snapshots'] is! List<Object?>) {
    throw const FormatException('Invalid history manifest.');
  }
  final entries = (value['snapshots']! as List<Object?>)
      .map((raw) => _historyEntryFromJson(raw! as Map<String, Object?>))
      .toList();
  return _HistoryManifest(
    historyKey: value['historyKey']! as String,
    relativePath: value['relativePath']! as String,
    format: value['format']! as String,
    entries: entries,
  );
}

_HistoryEntry _historyEntryFromJson(Map<String, Object?> value) {
  if (value['id'] is! String ||
      value['createdAt'] is! String ||
      value['trigger'] is! String ||
      value['contentHash'] is! String ||
      value['characterCount'] is! int ||
      value['byteSize'] is! int ||
      value['protected'] is! bool ||
      value['file'] is! String) {
    throw const FormatException('Invalid history snapshot entry.');
  }
  final trigger = HistoryTrigger.values.byName(value['trigger']! as String);
  return _HistoryEntry(
    snapshot: HistorySnapshot(
      id: value['id']! as String,
      createdAt: DateTime.parse(value['createdAt']! as String).toUtc(),
      trigger: trigger,
      contentHash: value['contentHash']! as String,
      characterCount: value['characterCount']! as int,
      isProtected: value['protected']! as bool,
      label: value['label'] as String?,
      note: value['note'] as String?,
    ),
    file: value['file']! as String,
    byteSize: value['byteSize']! as int,
  );
}

Map<String, Object?> _historyManifestToJson(_HistoryManifest manifest) => {
  'schemaVersion': 1,
  'historyKey': manifest.historyKey,
  'relativePath': manifest.relativePath,
  'format': manifest.format,
  'snapshots': manifest.entries.map(_historyEntryToJson).toList(),
};

Map<String, Object?> _historyEntryToJson(_HistoryEntry entry) {
  final snapshot = entry.snapshot;
  return {
    'id': snapshot.id,
    'createdAt': snapshot.createdAt.toUtc().toIso8601String(),
    'trigger': snapshot.trigger.name,
    'contentHash': snapshot.contentHash,
    'characterCount': snapshot.characterCount,
    'byteSize': entry.byteSize,
    'protected': snapshot.isProtected,
    'label': snapshot.label,
    'note': snapshot.note,
    'file': entry.file,
  };
}
