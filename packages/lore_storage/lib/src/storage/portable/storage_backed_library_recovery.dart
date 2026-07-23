part of '../storage_backed_library_repository.dart';

/// 结构变更的崩溃恢复。
///
/// rename/move/trash 等结构操作以 pending-operation 日志先行落盘，操作完成
/// 后清除；重启时 [_recoverPendingMutation] 依据日志与当前文件系统状态收敛，
/// 使崩溃至多回退到操作前的一致态。这组方法仅被主仓库类调用（无 sibling
/// mixin 依赖），故从 `_StorageBackedLibrarySupport` 拆出独立成 mixin，其余
/// codec/registry/scan 辅助因被多个 sibling mixin 经 `on` 依赖而留在原 mixin。
mixin _StorageBackedLibraryRecovery on _StorageBackedLibrarySupport {
  Future<void> _beginMutation(
    LibraryStorageSession storage, {
    required String operation,
    required NovelId novelId,
    required String novelPath,
    required LogicalPath source,
    required LogicalPath target,
  }) async {
    if (await storage.stat(_pendingOperation) != null) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.externalModification,
          message: '存在尚未恢复的结构操作，请重新打开书库。',
        ),
      );
    }
    await _ensurePortableDirectory(storage, _pendingOperation.parent!);
    await _writeNewJson(storage, _pendingOperation, {
      'schemaVersion': 2,
      'novelId': novelId.value,
      'novelPath': novelPath,
      'operation': operation,
      'sourcePath': source.value,
      'targetPath': target.value,
      'startedAt': clock.nowUtc().toIso8601String(),
    });
  }

  Future<void> _clearPendingMutation(LibraryStorageSession storage) async {
    if (await storage.stat(_pendingOperation) != null) {
      await storage.delete(_pendingOperation, recursive: false);
    }
  }

  Future<void> _recoverPendingMutation(LibraryStorageSession storage) async {
    if (await storage.stat(_pendingOperation) == null) {
      return;
    }
    final pending = await _readJson(storage, _pendingOperation);
    final novelIdValue = pending['novelId'];
    final novelPath = pending['novelPath'];
    final operation = pending['operation'];
    final sourceValue = pending['sourcePath'];
    final targetValue = pending['targetPath'];
    if (operation == 'trashNode' ||
        operation == 'trashNovel' ||
        operation == 'trashEntry' ||
        operation == 'restoreItem') {
      await _clearPendingMutation(storage);
      return;
    }
    if (novelIdValue is! String ||
        novelPath is! String ||
        operation is! String ||
        sourceValue is! String ||
        targetValue is! String) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.metadataCorrupt,
          message: '结构操作恢复记录已损坏。',
        ),
      );
    }
    final novelId = NovelId(novelIdValue);
    final source = LogicalPath.parse(sourceValue);
    final target = LogicalPath.parse(targetValue);
    if (operation == 'renameNovel') {
      final targetExists = await storage.stat(target) != null;
      final sourceExists = await storage.stat(source) != null;
      if (targetExists && !sourceExists) {
        final snapshot = await _loadNovel(
          storage,
          NovelRegistration(id: novelId, relativePath: target.value),
        );
        if (snapshot.metadata.title != target.name) {
          final metadata = _copyNovel(
            snapshot.metadata,
            revision: snapshot.metadata.revision + 1,
            title: target.name,
            updatedAt: clock.nowUtc(),
          );
          await _replaceJson(
            storage,
            target.child('.lore').child('novel.json'),
            _novelToJson(metadata),
          );
        }
        await _replaceRegistration(storage, novelId, target.value);
      }
      await _clearPendingMutation(storage);
      return;
    }
    final registration = await _registration(storage, novelId);
    final snapshot = await _loadNovel(storage, registration);
    if (operation == 'renameBody' &&
        await storage.stat(target) != null &&
        await storage.stat(source) == null) {
      final oldBody = source.value.substring(novelPath.length + 1);
      final newBody = target.value.substring(novelPath.length + 1);
      final metadata = _copyNovel(
        snapshot.metadata,
        revision: snapshot.metadata.revision + 1,
        body: NovelBody(id: snapshot.metadata.body.id, relativePath: newBody),
        updatedAt: clock.nowUtc(),
      );
      final nodes = snapshot.contentTree.nodes
          .map(
            (node) => node.copyWith(
              relativePath:
                  '$newBody/${node.relativePath.substring(oldBody.length + 1)}',
            ),
          )
          .toList(growable: false);
      await _writeNovelSnapshot(
        storage,
        novelPath,
        metadata,
        ContentTree(
          schemaVersion: 2,
          novelId: novelId,
          revision: snapshot.contentTree.revision + 1,
          nodes: nodes,
        ),
      );
    } else if (operation == 'renameNode' || operation == 'moveChapter') {
      final sourceExists = await storage.stat(source) != null;
      final targetExists = await storage.stat(target) != null;
      if (sourceExists && !targetExists) {
        await _clearPendingMutation(storage);
        return;
      }
      if (!targetExists) {
        await _clearPendingMutation(storage);
        return;
      }
      final scanned = await _scanTree(
        storage,
        LogicalPath.parse(novelPath),
        snapshot.metadata,
        snapshot.contentTree.nodes,
        revision: snapshot.contentTree.revision + 1,
      );
      await _replaceJson(
        storage,
        LogicalPath.parse('$novelPath/.lore/content.json'),
        _contentToJson(scanned),
      );
    }
    await _clearPendingMutation(storage);
  }

  Future<NovelStructureMutation> _commitNodes(
    LibraryStorageSession storage,
    NovelSnapshot snapshot,
    List<ContentNode> nodes,
    ContentNode changed,
  ) async {
    final tree = ContentTree(
      schemaVersion: 2,
      novelId: snapshot.metadata.id,
      revision: snapshot.contentTree.revision + 1,
      nodes: nodes,
    );
    await _replaceJson(
      storage,
      LogicalPath.parse('${snapshot.rootPath}/.lore/content.json'),
      _contentToJson(tree),
    );
    final updated = NovelSnapshot(
      rootPath: snapshot.rootPath,
      metadata: snapshot.metadata,
      contentTree: tree,
    );
    return NovelStructureMutation(
      snapshot: updated,
      entry: _contentEntry(updated, changed),
    );
  }
}
