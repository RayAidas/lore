part of '../storage_backed_library_repository.dart';

/// 历史版本的存储实现：list / record / readSnapshotText / deleteSnapshot。
///
/// record 内部做哈希去重：若正文 sha256 与该文档最新一条快照相同则跳过，返回
/// 既有快照。快照正文以 gzip 全量独立存储（非增量），单条损坏不影响其他版本。
/// 保留策略回收（prune）见阶段 3。
mixin _StorageBackedHistoryRepository
    on _StorageBackedLibrarySupport, _StorageBackedHistorySupport
    implements HistoryRepository {
  @override
  Future<List<HistorySnapshot>> list(
    LibraryAccess access,
    DocumentIdentity doc,
  ) async {
    try {
      final storage = await storageFactory.open(access);
      final manifest = await _readHistoryManifest(storage, doc);
      return manifest?.snapshots ?? const [];
    } catch (error) {
      if (_isExpectedHistoryReadFailure(error)) {
        // 历史列举只服务于面板展示，且历史本身是 best-effort：预期内的读取
        // 异常（manifest 缺失/损坏、权限、瞬态 IO 等）降级为空列表，避免把
        // 版本面板卡在错误态。打日志便于排查，不静默。
        stderr.writeln('[lore-history] list 失败 ${doc.relativePath}: $error');
        return const [];
      }
      rethrow;
    }
  }

  @override
  Future<HistorySnapshot> record(
    LibraryAccess access, {
    required DocumentIdentity doc,
    required String text,
    required HistoryTrigger trigger,
    String? label,
    String? note,
  }) async {
    final hash = _contentHashOf(text);
    final storage = await storageFactory.open(access);

    // 快速路径：若最新一条内容相同，直接返回，不写任何文件。
    final current = await _readHistoryManifest(storage, doc);
    final latest = current?.latest;
    if (latest != null && latest.snapshot.contentHash == hash) {
      return latest.snapshot;
    }

    // 先写 gzip 快照文件（孤儿无害：manifest 未引用的文件最多占少量空间，
    // 不影响正确性；manifest 是权威）。manifest 写入失败时不会留下「引用了
    // 不存在文件」的破损状态。
    final snapshotId = idGenerator.generate();
    final createdAt = clock.nowUtc();
    final fileName = _snapshotFileName(createdAt, snapshotId);
    final bytes = _gzipEncode(text);
    await _ensurePortableDirectory(storage, _historySnapshotsDir(doc));
    await storage.createFile(_historySnapshotsDir(doc).child(fileName), bytes);

    final isManual = trigger == HistoryTrigger.manual;
    final snapshot = HistorySnapshot(
      id: snapshotId,
      createdAt: createdAt,
      trigger: trigger,
      contentHash: hash,
      characterCount: characterCountOf(text),
      isProtected: isManual,
      label: isManual ? label : null,
      note: isManual ? note : null,
    );
    final entry = _HistoryEntry(
      snapshot: snapshot,
      file: fileName,
      byteSize: bytes.length,
    );

    // 写 manifest（乐观锁重试）。竞态下若另一进程已写入同内容，本次 entry
    // 被丢弃，刚写的快照文件成为孤儿（可接受）。
    final committed = await _modifyHistoryManifest(
      access,
      doc,
      mutate: (manifest) {
        if (manifest.latest?.snapshot.contentHash == hash) {
          return false;
        }
        manifest.entries.add(entry);
        return true;
      },
    );
    final committedLatest = committed.latest;
    if (committedLatest != null &&
        committedLatest.snapshot.contentHash == hash &&
        committedLatest.snapshot.id != snapshotId) {
      return committedLatest.snapshot;
    }
    return snapshot;
  }

  @override
  Future<String> readSnapshotText(
    LibraryAccess access, {
    required DocumentIdentity doc,
    required String snapshotId,
  }) async {
    final storage = await storageFactory.open(access);
    final manifest = await _readHistoryManifest(storage, doc);
    final entry = manifest?.entryById(snapshotId);
    if (entry == null) throw _notFound();
    try {
      final bytes = await storage.readBytes(
        _historySnapshotsDir(doc).child(entry.file),
      );
      return _gzipDecode(bytes);
    } on Object {
      // 快照文件丢失或损坏（被外部删除 / gzip 解压失败）。manifest 仍引用它，
      // 但磁盘不可读——按 notFound 上报，让 UI 提示而非崩溃。
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.notFound,
          message: '快照文件已丢失或损坏。',
        ),
      );
    }
  }

  @override
  Future<void> deleteSnapshot(
    LibraryAccess access, {
    required DocumentIdentity doc,
    required String snapshotId,
  }) async {
    String? removedFile;
    await _modifyHistoryManifest(
      access,
      doc,
      mutate: (manifest) {
        final index = manifest.entries.indexWhere(
          (entry) => entry.snapshot.id == snapshotId,
        );
        if (index < 0) return false;
        removedFile = manifest.entries[index].file;
        manifest.entries.removeAt(index);
        return true;
      },
    );
    // best-effort 删除 gzip 文件；manifest 已不再引用，文件缺失不影响正确性。
    final file = removedFile;
    if (file != null) {
      final storage = await storageFactory.open(access);
      final path = _historySnapshotsDir(doc).child(file);
      if (await storage.stat(path) != null) {
        await storage.delete(path, recursive: false);
      }
    }
  }

  @override
  Future<void> prune(LibraryAccess access, DocumentIdentity doc) async {
    final now = clock.nowUtc();
    final removed = <_HistoryEntry>[];
    try {
      await _modifyHistoryManifest(
        access,
        doc,
        mutate: (manifest) {
          // 每次重试重填：基于当前 manifest 算保留集与淘汰集。
          removed.clear();
          final auto = manifest.entries
              .where((entry) => !entry.snapshot.isProtected)
              .map((entry) => entry.snapshot)
              .toList();
          final retainIds = retainAutoSnapshotIds(auto, now).toSet();
          for (final entry in manifest.entries) {
            if (!entry.snapshot.isProtected &&
                !retainIds.contains(entry.snapshot.id)) {
              removed.add(entry);
            }
          }
          if (removed.isEmpty) return false;
          manifest.entries.removeWhere(
            (entry) =>
                !entry.snapshot.isProtected &&
                !retainIds.contains(entry.snapshot.id),
          );
          return true;
        },
      );
    } on LibraryOperationException catch (error) {
      // best-effort：并发改写时放弃本次回收，下次 record 后会再触发。
      if (error.failure.code == LibraryFailureCode.externalModification) {
        return;
      }
      rethrow;
    }
    // best-effort 删除被淘汰的 gzip 文件（仅在 manifest 提交成功后执行）。
    if (removed.isEmpty) return;
    final storage = await storageFactory.open(access);
    for (final entry in removed) {
      final path = _historySnapshotsDir(doc).child(entry.file);
      if (await storage.stat(path) != null) {
        await storage.delete(path, recursive: false);
      }
    }
  }
}
