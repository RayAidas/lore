part of '../storage_backed_library_repository.dart';

mixin _StorageBackedTrashSupport on _StorageBackedLibrarySupport {
  Future<void> _ensureTrash(LibraryStorageSession storage, String token) async {
    if (await storage.stat(_trashRoot) == null) {
      await storage.createDirectory(_trashRoot);
    }
    final tokenRoot = _trashRoot.child(token);
    if (await storage.stat(tokenRoot) == null) {
      await storage.createDirectory(tokenRoot);
    }
  }

  Future<void> _ensureTrashParents(
    LibraryStorageSession storage,
    String token,
    LogicalPath source,
  ) async {
    var current = _trashRoot.child(token);
    final segments = source.value.split('/');
    for (final segment in segments.take(segments.length - 1)) {
      current = current.child(segment);
      if (await storage.stat(current) == null) {
        await storage.createDirectory(current);
      }
    }
  }

  LogicalPath _trashTarget(String token, LogicalPath source) {
    var result = _trashRoot.child(token);
    for (final segment in source.value.split('/')) {
      result = result.child(segment);
    }
    return result;
  }

  Future<List<_TrashRecord>> _trashRecords(
    LibraryStorageSession storage,
  ) async {
    final records = <_TrashRecord>[];
    if (await storage.stat(_trashManifest) != null) {
      final value = await _readJson(storage, _trashManifest);
      records.addAll(
        (value['items'] as List<Object?>? ?? const []).map(
          (raw) => _TrashRecord.fromJson(raw! as Map<String, Object?>),
        ),
      );
    }
    var changed = false;
    for (final record in List<_TrashRecord>.of(records)) {
      final trashExists =
          await storage.stat(
            LogicalPath.parse(record.item.trashRelativePath),
          ) !=
          null;
      if (record.pending && trashExists) {
        records[records.indexOf(record)] = record.copyWith(pending: false);
        changed = true;
      } else if (!trashExists) {
        records.remove(record);
        changed = true;
      }
    }
    if (await storage.stat(_trashRoot) != null) {
      final knownTokens = records.map((record) => record.item.token).toSet();
      for (final entry in await storage.list(_trashRoot)) {
        if (entry.type != StorageEntryType.directory ||
            knownTokens.contains(entry.path.name)) {
          continue;
        }
        final children = await storage.list(entry.path);
        final visible = children
            .where((child) => !child.path.name.startsWith('.'))
            .firstOrNull;
        if (visible == null) continue;
        records.add(
          _TrashRecord(
            item: TrashItem(
              token: entry.path.name,
              type: TrashItemType.entry,
              originalRelativePath: visible.path.name,
              trashRelativePath: visible.path.value,
              deletedAt: clock.nowUtc(),
              restorable: true,
            ),
          ),
        );
        changed = true;
      }
    }
    if (changed) await _writeTrashRecords(storage, records);
    return records;
  }

  Future<void> _appendTrash(
    LibraryStorageSession storage,
    _TrashRecord record,
  ) async {
    final records = await _trashRecords(storage)
      ..add(record);
    await _writeTrashRecords(storage, records);
  }

  Future<void> _removeTrashRecord(
    LibraryStorageSession storage,
    String token,
  ) async {
    final records = await _trashRecords(storage)
      ..removeWhere((record) => record.item.token == token);
    await _writeTrashRecords(storage, records);
  }

  Future<void> _markTrashCommitted(
    LibraryStorageSession storage,
    String token,
  ) async {
    final records = await _trashRecords(storage);
    final index = records.indexWhere((record) => record.item.token == token);
    if (index < 0) throw _notFound();
    if (records[index].pending) {
      records[index] = records[index].copyWith(pending: false);
      await _writeTrashRecords(storage, records);
    }
  }

  Future<void> _writeTrashRecords(
    LibraryStorageSession storage,
    List<_TrashRecord> records,
  ) async {
    final value = {
      'schemaVersion': 2,
      'items': records.map((record) => record.toJson()).toList(),
    };
    if (await storage.stat(_trashManifest) == null) {
      await _writeNewJson(storage, _trashManifest, value);
    } else {
      await _replaceJson(storage, _trashManifest, value);
    }
  }

  Future<LogicalPath> _availableRestorePath(
    LibraryStorageSession storage,
    LogicalPath original,
  ) async {
    final extension = _extension(original.name);
    final stem = extension.isEmpty
        ? original.name
        : original.name.substring(0, original.name.length - extension.length);
    for (var index = 1; ; index += 1) {
      final candidate = original.parent!.child('$stem (恢复 $index)$extension');
      if (await storage.stat(candidate) == null) return candidate;
    }
  }

  TrashItem _copyTrashItem(TrashItem item, {required String originalPath}) =>
      TrashItem(
        token: item.token,
        type: item.type,
        originalRelativePath: originalPath,
        trashRelativePath: item.trashRelativePath,
        deletedAt: item.deletedAt,
        restorable: item.restorable,
        novelId: item.novelId,
        nodeId: item.nodeId,
        novelRootPath: item.novelRootPath,
        children: item.children,
      );
}

final class _TrashRecord {
  const _TrashRecord({
    required this.item,
    this.nodes = const [],
    this.pending = false,
  });

  final TrashItem item;
  final List<ContentNode> nodes;
  final bool pending;

  factory _TrashRecord.fromJson(Map<String, Object?> value) {
    final originalPath = value['originalPath'] ?? value['originalRelativePath'];
    final trashPath = value['trashPath'] ?? value['trashRelativePath'];
    return _TrashRecord(
      pending: value['pending'] == true,
      item: TrashItem(
        token: value['token']! as String,
        type: TrashItemType.values.byName(value['type']! as String),
        originalRelativePath: originalPath! as String,
        trashRelativePath: trashPath! as String,
        deletedAt: DateTime.parse(value['deletedAt']! as String).toUtc(),
        restorable: value['restorable'] as bool? ?? true,
        novelId: value['novelId'] as String?,
        nodeId: value['nodeId'] as String?,
        novelRootPath: value['novelRootPath'] as String?,
        children: (value['children'] as List<Object?>? ?? const [])
            .map((raw) {
              final child = raw! as Map<String, Object?>;
              return TrashItemChild(
                nodeId: child['nodeId']! as String,
                originalRelativePath: child['originalRelativePath']! as String,
                trashRelativePath: child['trashRelativePath']! as String,
              );
            })
            .toList(growable: false),
      ),
      nodes: (value['nodes'] as List<Object?>? ?? const []).map((raw) {
        final node = raw! as Map<String, Object?>;
        return ContentNode(
          id: ContentId(node['id']! as String),
          type: ContentNodeType.values.byName(node['type']! as String),
          parentId: ContentId(node['parentId']! as String),
          relativePath: node['path']! as String,
          order: node['order']! as int,
          number: node['number'] as int?,
          role: ContentRole.values.byName(node['role']! as String),
        );
      }).toList(),
    );
  }

  Map<String, Object?> toJson() => {
    'pending': pending,
    'token': item.token,
    'type': item.type.name,
    'originalPath': item.originalRelativePath,
    'trashPath': item.trashRelativePath,
    'deletedAt': item.deletedAt.toUtc().toIso8601String(),
    'novelId': item.novelId,
    'nodeId': item.nodeId,
    'novelRootPath': item.novelRootPath,
    'nodes': nodes
        .map(
          (node) => {
            'id': node.id.value,
            'type': node.type.name,
            'parentId': node.parentId.value,
            'path': node.relativePath,
            'order': node.order,
            'number': node.number,
            'role': node.role.name,
          },
        )
        .toList(),
  };

  _TrashRecord copyWith({bool? pending}) =>
      _TrashRecord(item: item, nodes: nodes, pending: pending ?? this.pending);
}
