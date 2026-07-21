part of '../storage_backed_library_repository.dart';

/// 文字高亮的存储实现:聚合到 `<novel>/.lore/highlights.json`,以文档
/// relativePath([documentId])为键索引。复用 [_readJson]/[_writeNewJson]/
/// [_replaceJson] 的乐观锁写法,与 `library.json`/`novel.json`/`content.json`
/// 同构;`highlights.json` 不进 [StorageSchemaMigrator] 的备份列表(与
/// trash/recovery 一致,属小说级派生数据)。
///
/// 结构:
/// ```
/// { "schemaVersion": 1,
///   "documents": {
///     "<relativePath>": {
///       "revision": "<document sha256>",
///       "paragraphDigests": ["...", ...],
///       "highlights": [{"id","start","end","color","anchor"}] } } }
/// ```
mixin _StorageBackedHighlightRepository on _StorageBackedLibrarySupport
    implements HighlightRepository {
  Future<LogicalPath> _highlightsPath(
    LibraryStorageSession storage,
    NovelId novelId,
  ) async {
    final registration = await _registration(storage, novelId);
    return LogicalPath.parse(
      '${registration.relativePath}/.lore/highlights.json',
    );
  }

  @override
  Future<HighlightCollection?> loadHighlights(
    LibraryAccess access, {
    required NovelId novelId,
    required String documentId,
  }) async {
    final storage = await storageFactory.open(access);
    final path = await _highlightsPath(storage, novelId);
    if (await storage.stat(path) == null) return null;
    final root = await _readJson(storage, path);
    final documents = root['documents'];
    if (documents is! Map<String, Object?>) return null;
    final entry = documents[documentId];
    if (entry is! Map<String, Object?>) return null;
    return _highlightCollectionFromJson(entry);
  }

  @override
  Future<void> saveHighlights(
    LibraryAccess access, {
    required NovelId novelId,
    required String documentId,
    required HighlightCollection collection,
  }) async {
    final entry = _highlightCollectionToJson(collection);
    await _modifyHighlightsFile(
      access,
      novelId: novelId,
      createIfMissing: true,
      newDocumentsOnCreate: {documentId: entry},
      mutate: (documents) {
        documents[documentId] = entry;
        return true;
      },
    );
  }

  @override
  Future<void> moveHighlights(
    LibraryAccess access, {
    required NovelId novelId,
    required String oldDocumentId,
    required String newDocumentId,
  }) async {
    if (oldDocumentId == newDocumentId) return;
    await _modifyHighlightsFile(
      access,
      novelId: novelId,
      createIfMissing: false,
      newDocumentsOnCreate: const {},
      mutate: (documents) {
        if (!documents.containsKey(oldDocumentId)) return false;
        documents[newDocumentId] = documents.remove(oldDocumentId);
        return true;
      },
    );
  }

  @override
  Future<void> deleteHighlights(
    LibraryAccess access, {
    required NovelId novelId,
    required String documentId,
  }) async {
    await _modifyHighlightsFile(
      access,
      novelId: novelId,
      createIfMissing: false,
      newDocumentsOnCreate: const {},
      mutate: (documents) {
        if (!documents.containsKey(documentId)) return false;
        documents.remove(documentId);
        return true;
      },
      deleteFileWhenEmpty: true,
    );
  }

  /// 统一的 read-modify-write + 乐观锁重试。并发改写(externalModification)
  /// 或首次写竞态(alreadyExists)时重读重试,最多 [_highlightWriteAttempts]
  /// 次;仍失败才抛,让调用方上报。覆盖 save/move/delete 三个写入入口。
  Future<void> _modifyHighlightsFile(
    LibraryAccess access, {
    required NovelId novelId,
    required bool createIfMissing,
    required Map<String, Object?> newDocumentsOnCreate,
    required bool Function(Map<String, Object?> documents) mutate,
    bool deleteFileWhenEmpty = false,
  }) async {
    var attempt = 0;
    while (true) {
      attempt += 1;
      final storage = await storageFactory.open(access);
      final path = await _highlightsPath(storage, novelId);
      final stat = await storage.stat(path);
      try {
        if (stat == null) {
          if (!createIfMissing) return;
          await _writeNewJson(storage, path, {
            'schemaVersion': 1,
            'documents': newDocumentsOnCreate,
          });
          return;
        }
        final root = await _readJson(storage, path);
        final existing = root['documents'];
        final documents = existing is Map<String, Object?>
            ? Map<String, Object?>.from(existing)
            : <String, Object?>{};
        if (!mutate(documents)) return;
        if (deleteFileWhenEmpty && documents.isEmpty) {
          await storage.delete(path, recursive: false);
        } else {
          root['documents'] = documents;
          await _replaceJson(storage, path, root);
        }
        return;
      } on LibraryOperationException catch (error) {
        final code = error.failure.code;
        final retriable = code == LibraryFailureCode.externalModification ||
            code == LibraryFailureCode.alreadyExists;
        if (!retriable || attempt >= _highlightWriteAttempts) rethrow;
      }
    }
  }

  static const _highlightWriteAttempts = 3;
}

Map<String, Object?> _highlightCollectionToJson(HighlightCollection c) => {
  'revision': c.documentRevision,
  'paragraphDigests': c.paragraphDigests,
  'highlights': c.highlights.map(_highlightToJson).toList(),
};

Map<String, Object?> _highlightToJson(Highlight h) => {
  'id': h.id,
  'start': h.start,
  'end': h.end,
  'color': h.colorArgb,
  'anchor': h.anchorText,
};

HighlightCollection? _highlightCollectionFromJson(Map<String, Object?> json) {
  final revision = json['revision'];
  if (revision is! String) return null;
  final digestRaw = json['paragraphDigests'];
  final digests = digestRaw is List
      ? [for (final d in digestRaw) if (d is String) d]
      : <String>[];
  final highlightsRaw = json['highlights'];
  final highlights = <Highlight>[];
  if (highlightsRaw is List) {
    for (final raw in highlightsRaw) {
      if (raw is Map<String, Object?>) {
        final parsed = _highlightFromJson(raw);
        if (parsed != null) highlights.add(parsed);
      }
    }
  }
  return HighlightCollection(
    documentRevision: revision,
    paragraphDigests: digests,
    highlights: highlights,
  );
}

Highlight? _highlightFromJson(Map<String, Object?> json) {
  final id = json['id'];
  final start = json['start'];
  final end = json['end'];
  final color = json['color'];
  final anchor = json['anchor'];
  if (id is! String ||
      start is! int ||
      end is! int ||
      color is! int ||
      anchor is! String) {
    return null;
  }
  return Highlight(
    id: id,
    start: start,
    end: end,
    colorArgb: color,
    anchorText: anchor,
  );
}
