part of '../storage_backed_library_repository.dart';

mixin _StorageBackedTrashRepository
    on _StorageBackedLibrarySupport, _StorageBackedTrashSupport
    implements TrashRepository {
  @override
  Future<List<TrashItem>> listItems(LibraryAccess access) async {
    final storage = await storageFactory.open(access);
    return (await _trashRecords(storage)).map((record) => record.item).toList();
  }

  @override
  Future<TrashItem> restore(
    LibraryAccess access, {
    required String trashToken,
    RestoreConflictStrategy strategy = RestoreConflictStrategy.rename,
  }) async {
    final storage = await storageFactory.open(access);
    final records = await _trashRecords(storage);
    final index = records.indexWhere(
      (record) => record.item.token == trashToken,
    );
    if (index < 0) throw _notFound();
    final record = records[index];
    final source = LogicalPath.parse(record.item.trashRelativePath);
    var target = LogicalPath.parse(record.item.originalRelativePath);
    if (await storage.stat(target) != null) {
      switch (strategy) {
        case RestoreConflictStrategy.skip:
          return record.item;
        case RestoreConflictStrategy.overwrite:
          await storage.delete(target, recursive: true);
        case RestoreConflictStrategy.rename:
          target = await _availableRestorePath(storage, target);
      }
    }
    await storage.move(source, target);
    if (record.item.type == TrashItemType.novel &&
        record.item.novelId != null) {
      await _addRegistration(
        storage,
        NovelRegistration(
          id: NovelId(record.item.novelId!),
          relativePath: target.value,
        ),
      );
    } else if (record.item.novelId != null &&
        record.item.novelRootPath != null &&
        (record.item.type == TrashItemType.chapter ||
            record.item.type == TrashItemType.volume)) {
      final registration = await _registration(
        storage,
        NovelId(record.item.novelId!),
      );
      final snapshot = await _loadNovel(storage, registration);
      final existing = record.nodes.isEmpty
          ? _legacyRestoreSeeds(snapshot, record.item, target)
          : _restoredNodes(snapshot, record, target);
      final tree = await _scanTree(
        storage,
        LogicalPath.parse(snapshot.rootPath),
        snapshot.metadata,
        [...snapshot.contentTree.nodes, ...existing],
        revision: snapshot.contentTree.revision + 1,
      );
      await _replaceJson(
        storage,
        LogicalPath.parse('${snapshot.rootPath}/.lore/content.json'),
        _contentToJson(tree),
      );
    }
    final tokenRoot = _trashRoot.child(trashToken);
    if (await storage.stat(tokenRoot) != null) {
      await storage.delete(tokenRoot, recursive: true);
    }
    records.removeAt(index);
    await _writeTrashRecords(storage, records);
    return _copyTrashItem(record.item, originalPath: target.value);
  }

  List<ContentNode> _restoredNodes(
    NovelSnapshot snapshot,
    _TrashRecord record,
    LogicalPath target,
  ) {
    final original = LogicalPath.parse(record.item.originalRelativePath);
    return record.nodes
        .map((node) {
          final originalNodePath = LogicalPath.parse(
            '${snapshot.rootPath}/${node.relativePath}',
          );
          if (originalNodePath != original &&
              !original.contains(originalNodePath)) {
            return node;
          }
          final suffix = originalNodePath.value.substring(
            original.value.length,
          );
          return node.copyWith(
            relativePath: '${target.value}$suffix'.substring(
              snapshot.rootPath.length + 1,
            ),
          );
        })
        .toList(growable: false);
  }

  List<ContentNode> _legacyRestoreSeeds(
    NovelSnapshot snapshot,
    TrashItem item,
    LogicalPath target,
  ) {
    final nodeId = item.nodeId;
    if (nodeId == null) return const [];
    final rootId = ContentId(nodeId);
    final rootRelative = target.value.substring(snapshot.rootPath.length + 1);
    final rootParent = item.type == TrashItemType.volume
        ? snapshot.metadata.body.id
        : _parentIdForPath(snapshot, rootRelative);
    final seeds = <ContentNode>[
      ContentNode(
        id: rootId,
        type: item.type == TrashItemType.volume
            ? ContentNodeType.volume
            : ContentNodeType.chapter,
        parentId: rootParent,
        relativePath: rootRelative,
        order: _nextOrder(snapshot.contentTree.childrenOf(rootParent)),
        number: item.type == TrashItemType.chapter
            ? _chapterNumber(rootRelative)
            : null,
        role: item.type == TrashItemType.chapter
            ? _chapterRole(rootRelative)
            : ContentRole.normal,
      ),
    ];
    var childOrder = 1000;
    for (final child in item.children) {
      final suffix = child.originalRelativePath.substring(
        item.originalRelativePath.length,
      );
      final relativePath = '${target.value}$suffix'.substring(
        snapshot.rootPath.length + 1,
      );
      seeds.add(
        ContentNode(
          id: ContentId(child.nodeId),
          type: ContentNodeType.chapter,
          parentId: rootId,
          relativePath: relativePath,
          order: childOrder,
          number: _chapterNumber(relativePath),
          role: _chapterRole(relativePath),
        ),
      );
      childOrder += 1000;
    }
    return seeds;
  }

  ContentId _parentIdForPath(NovelSnapshot snapshot, String relativePath) {
    final parentPath = LogicalPath.parse(relativePath).parent!.value;
    if (parentPath == snapshot.metadata.body.relativePath) {
      return snapshot.metadata.body.id;
    }
    return snapshot.contentTree.nodes
        .firstWhere(
          (node) =>
              node.type == ContentNodeType.volume &&
              node.relativePath == parentPath,
          orElse: () => throw _metadataCorrupt(),
        )
        .id;
  }

  @override
  Future<void> purge(LibraryAccess access, {required String trashToken}) async {
    final storage = await storageFactory.open(access);
    final records = await _trashRecords(storage);
    final index = records.indexWhere(
      (record) => record.item.token == trashToken,
    );
    if (index < 0) throw _notFound();
    final tokenRoot = _trashRoot.child(trashToken);
    if (await storage.stat(tokenRoot) != null) {
      await storage.delete(tokenRoot, recursive: true);
    }
    records.removeAt(index);
    await _writeTrashRecords(storage, records);
  }

  @override
  Future<void> empty(LibraryAccess access) async {
    final storage = await storageFactory.open(access);
    final records = await _trashRecords(storage);
    for (final record in records) {
      final tokenRoot = _trashRoot.child(record.item.token);
      if (await storage.stat(tokenRoot) != null) {
        await storage.delete(tokenRoot, recursive: true);
      }
    }
    await _writeTrashRecords(storage, const []);
  }
}
