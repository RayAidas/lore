import 'dart:convert';
import 'dart:typed_data';

import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';

import 'storage_schema_migrator.dart';

/// Portable semantic repository used by non-path storage backends such as SAF.
final class StorageBackedLibraryRepository
    implements
        LibraryRepository,
        LibraryTreeRepository,
        DocumentRepository,
        NovelRepository,
        ContentTreeRepository,
        TrashRepository {
  const StorageBackedLibraryRepository({
    required this.storageFactory,
    required this.idGenerator,
    required this.clock,
  });

  final LibraryStorageFactory storageFactory;
  final IdGenerator idGenerator;
  final Clock clock;

  static final _metadata = LogicalPath.parse('.lore');
  static final _libraryManifest = LogicalPath.parse('.lore/library.json');
  static final _trashRoot = LogicalPath.parse('.lore/trash');
  static final _trashManifest = LogicalPath.parse('.lore/trash/index.json');

  @override
  Future<LibraryInspection> inspect(LibraryAccess access) async {
    try {
      final storage = await storageFactory.open(access);
      if (await storage.stat(_libraryManifest) == null) {
        return const LibraryInspectionNeedsInitialization();
      }
      await StorageSchemaMigrator(
        idGenerator: idGenerator,
      ).migrateIfNeeded(storage);
      final value = await _readJson(storage, _libraryManifest);
      if (value['schemaVersion'] != 2 ||
          value['revision'] is! int ||
          value['libraryId'] is! String ||
          value['createdAt'] is! String ||
          value['updatedAt'] is! String ||
          value['novels'] is! List<Object?>) {
        return const LibraryInspectionFailure(
          LibraryFailure(
            code: LibraryFailureCode.metadataCorrupt,
            message: '书库元数据无效。',
          ),
        );
      }
      return LibraryInspectionReady(_libraryFromJson(value));
    } on LibraryOperationException catch (error) {
      return LibraryInspectionFailure(error.failure);
    } on FormatException {
      return const LibraryInspectionFailure(
        LibraryFailure(
          code: LibraryFailureCode.metadataCorrupt,
          message: '书库元数据无效。',
        ),
      );
    } on Object {
      return const LibraryInspectionFailure(
        LibraryFailure(code: LibraryFailureCode.io, message: '无法读取书库。'),
      );
    }
  }

  @override
  Future<LibraryMetadata> initialize(LibraryAccess access) async {
    final storage = await storageFactory.open(access);
    final existing = await inspect(access);
    if (existing case LibraryInspectionReady(:final metadata)) {
      return metadata;
    }
    if (existing case LibraryInspectionFailure(:final failure)) {
      throw LibraryOperationException(failure);
    }
    if (await storage.stat(_metadata) == null) {
      await storage.createDirectory(_metadata);
    }
    final now = clock.nowUtc();
    final metadata = LibraryMetadata(
      schemaVersion: 2,
      revision: 0,
      id: LibraryId(idGenerator.generate()),
      createdAt: now,
      updatedAt: now,
    );
    await _writeNewJson(storage, _libraryManifest, _libraryToJson(metadata));
    return metadata;
  }

  @override
  Future<List<LibraryEntry>> listChildren(
    LibraryAccess access, {
    String relativePath = '',
  }) async {
    final storage = await storageFactory.open(access);
    final directory = LogicalPath.parse(relativePath);
    final entries = <LibraryEntry>[];
    for (final item in await storage.list(directory)) {
      if (item.path.name.startsWith('.')) {
        continue;
      }
      entries.add(
        LibraryEntry(
          name: item.path.name,
          relativePath: item.path.value,
          type: _entryType(item),
        ),
      );
    }
    final novels = await listNovels(access);
    return entries.map((entry) => _annotateEntry(entry, novels)).toList()
      ..sort((left, right) {
        if (left.semanticOrder != null && right.semanticOrder != null) {
          return left.semanticOrder!.compareTo(right.semanticOrder!);
        }
        if (left.isDirectory != right.isDirectory) {
          return left.isDirectory ? -1 : 1;
        }
        return left.name.toLowerCase().compareTo(right.name.toLowerCase());
      });
  }

  @override
  Future<LibraryEntry> createDirectory(
    LibraryAccess access, {
    required String parentPath,
    required String name,
  }) async {
    final storage = await storageFactory.open(access);
    final target = _child(parentPath, _validName(name));
    await storage.createDirectory(target);
    return _entry(target, StorageEntryType.directory);
  }

  @override
  Future<LibraryEntry> createDocument(
    LibraryAccess access, {
    required String parentPath,
    required String name,
    required DocumentFormat format,
    String initialText = '',
  }) async {
    final storage = await storageFactory.open(access);
    final extension = format == DocumentFormat.text ? '.txt' : '.md';
    final valid = _validName(name);
    final fileName = valid.toLowerCase().endsWith(extension)
        ? valid
        : '$valid$extension';
    final target = _child(parentPath, fileName);
    await storage.createFile(
      target,
      Uint8List.fromList(utf8.encode(initialText)),
    );
    return _entry(target, StorageEntryType.file);
  }

  @override
  Future<LibraryEntry> renameEntry(
    LibraryAccess access, {
    required String relativePath,
    required String newName,
  }) async {
    final storage = await storageFactory.open(access);
    final source = LogicalPath.parse(relativePath);
    final sourceEntry = await storage.stat(source);
    if (sourceEntry == null) {
      throw _notFound();
    }
    var valid = _validName(newName);
    if (sourceEntry.type == StorageEntryType.file) {
      final extension = _extension(source.name);
      if (extension.isNotEmpty &&
          !_extension(valid).toLowerCase().endsWith(extension.toLowerCase())) {
        valid = '$valid$extension';
      }
    }
    final target = source.parent!.child(valid);
    await storage.move(source, target);
    return _entry(target, sourceEntry.type);
  }

  @override
  Future<DeletionResult> deleteEntry(
    LibraryAccess access, {
    required String relativePath,
  }) async {
    final storage = await storageFactory.open(access);
    final source = LogicalPath.parse(relativePath);
    final token = idGenerator.generate();
    final target = _trashTarget(token, source);
    await _ensureTrash(storage, token);
    final record = _TrashRecord(
      pending: true,
      item: TrashItem(
        token: token,
        type: TrashItemType.entry,
        originalRelativePath: source.value,
        trashRelativePath: target.value,
        deletedAt: clock.nowUtc(),
        restorable: true,
      ),
    );
    await _appendTrash(storage, record);
    try {
      await _ensureTrashParents(storage, token, source);
      await storage.move(source, target);
    } on Object {
      await _removeTrashRecord(storage, token);
      rethrow;
    }
    await _markTrashCommitted(storage, token);
    return DeletionResult(
      trashToken: token,
      removedNodeIds: const [],
      pathChanges: [PathChange(oldPath: source.value, newPath: target.value)],
    );
  }

  @override
  Future<DocumentSnapshot> readDocument(
    LibraryAccess access,
    DocumentRef ref,
  ) async {
    final storage = await storageFactory.open(access);
    final path = LogicalPath.parse(ref.relativePath);
    for (var attempt = 0; attempt < 2; attempt += 1) {
      final before = await storage.stat(path);
      if (before?.type != StorageEntryType.file || before?.revision == null) {
        throw _notFound();
      }
      final bytes = await storage.readBytes(path);
      final after = await storage.stat(path);
      if (after?.revision != before!.revision) {
        continue;
      }
      final hasBom =
          bytes.length >= 3 &&
          bytes[0] == 0xEF &&
          bytes[1] == 0xBB &&
          bytes[2] == 0xBF;
      final content = hasBom ? bytes.sublist(3) : bytes;
      final text = utf8.decode(content);
      return DocumentSnapshot(
        ref: ref,
        text: text,
        encoding: hasBom ? TextEncoding.utf8Bom : TextEncoding.utf8,
        lineEnding: _lineEnding(text),
        revision: DocumentRevision(after!.revision!),
      );
    }
    throw const LibraryOperationException(
      LibraryFailure(
        code: LibraryFailureCode.externalModification,
        message: '文档读取期间持续发生外部修改，请重试。',
      ),
    );
  }

  @override
  Future<DocumentSaveResult> saveDocument(
    LibraryAccess access, {
    required DocumentSnapshot original,
    required String text,
  }) async {
    final storage = await storageFactory.open(access);
    final normalized = _applyLineEnding(text, original.lineEnding);
    final encoded = utf8.encode(normalized);
    final bytes = Uint8List.fromList(
      original.encoding == TextEncoding.utf8Bom
          ? [0xEF, 0xBB, 0xBF, ...encoded]
          : encoded,
    );
    final result = await storage.replaceFile(
      LogicalPath.parse(original.ref.relativePath),
      expectedRevision: original.revision.value,
      bytes: bytes,
    );
    if (result case StorageReplaceConflict()) {
      return DocumentSaveConflict(await readDocument(access, original.ref));
    }
    return DocumentSaveSuccess(
      DocumentSnapshot(
        ref: original.ref,
        text: text,
        encoding: original.encoding,
        lineEnding: original.lineEnding,
        revision: DocumentRevision((result as StorageReplaceSuccess).revision),
      ),
    );
  }

  @override
  Stream<DocumentChange> watchDocuments(LibraryAccess access) async* {
    final storage = await storageFactory.open(access);
    await for (final change in storage.watch()) {
      yield DocumentChange(
        relativePath: change.path.value,
        type: switch (change.type) {
          StorageChangeType.created => DocumentChangeType.created,
          StorageChangeType.modified => DocumentChangeType.modified,
          StorageChangeType.deleted => DocumentChangeType.deleted,
          StorageChangeType.moved => DocumentChangeType.moved,
        },
      );
    }
  }

  @override
  Future<List<NovelSnapshot>> listNovels(LibraryAccess access) async {
    final storage = await storageFactory.open(access);
    final library = await _readJson(storage, _libraryManifest);
    final result = <NovelSnapshot>[];
    for (final registration in _registrations(library)) {
      try {
        result.add(await _loadNovel(storage, registration));
      } on Object {
        continue;
      }
    }
    return result;
  }

  @override
  Future<NovelSnapshot> loadNovel(
    LibraryAccess access, {
    required NovelId novelId,
  }) async {
    final storage = await storageFactory.open(access);
    return _loadNovel(storage, await _registration(storage, novelId));
  }

  @override
  Future<NovelStructureMutation> createNovel(
    LibraryAccess access, {
    required String title,
    ChapterFormat chapterFormat = ChapterFormat.markdown,
  }) async {
    final storage = await storageFactory.open(access);
    final validTitle = _validName(title);
    final root = LogicalPath.parse(validTitle);
    await storage.createDirectory(root);
    await storage.createDirectory(root.child('.lore'));
    await storage.createDirectory(root.child('正文'));
    final now = clock.nowUtc();
    final metadata = NovelMetadata(
      schemaVersion: 2,
      revision: 0,
      id: NovelId(idGenerator.generate()),
      title: validTitle,
      description: '',
      coverPath: null,
      body: NovelBody(
        id: ContentId(idGenerator.generate()),
        relativePath: '正文',
      ),
      chapterFormat: chapterFormat,
      numberingMode: NumberingMode.continuous,
      createdAt: now,
      updatedAt: now,
    );
    final tree = ContentTree(
      schemaVersion: 2,
      novelId: metadata.id,
      revision: 0,
      nodes: const [],
    );
    await _writeNewJson(
      storage,
      root.child('.lore').child('novel.json'),
      _novelToJson(metadata),
    );
    await _writeNewJson(
      storage,
      root.child('.lore').child('content.json'),
      _contentToJson(tree),
    );
    await _addRegistration(
      storage,
      NovelRegistration(id: metadata.id, relativePath: root.value),
    );
    final snapshot = NovelSnapshot(
      rootPath: root.value,
      metadata: metadata,
      contentTree: tree,
    );
    return NovelStructureMutation(
      snapshot: snapshot,
      entry: _novelEntry(snapshot),
    );
  }

  @override
  Future<NovelStructureMutation> registerExistingNovel(
    LibraryAccess access, {
    required String relativePath,
  }) async {
    final storage = await storageFactory.open(access);
    final root = LogicalPath.parse(relativePath);
    if (root.parent != LogicalPath.root) {
      throw _invalid('小说目录必须位于书库根级。');
    }
    final metadataRoot = root.child('.lore');
    if (await storage.stat(metadataRoot) == null) {
      await storage.createDirectory(metadataRoot);
    }
    final novelPath = metadataRoot.child('novel.json');
    final contentPath = metadataRoot.child('content.json');
    NovelMetadata metadata;
    if (await storage.stat(novelPath) == null) {
      if (await storage.stat(root.child('正文')) == null) {
        await storage.createDirectory(root.child('正文'));
      }
      final now = clock.nowUtc();
      metadata = NovelMetadata(
        schemaVersion: 2,
        revision: 0,
        id: NovelId(idGenerator.generate()),
        title: root.name,
        description: '',
        coverPath: null,
        body: NovelBody(
          id: ContentId(idGenerator.generate()),
          relativePath: '正文',
        ),
        chapterFormat: ChapterFormat.markdown,
        numberingMode: NumberingMode.continuous,
        createdAt: now,
        updatedAt: now,
      );
      await _writeNewJson(storage, novelPath, _novelToJson(metadata));
    } else {
      metadata = _novelFromJson(await _readJson(storage, novelPath));
    }
    ContentTree tree;
    if (await storage.stat(contentPath) == null) {
      tree = await _scanTree(storage, root, metadata, const [], revision: 0);
      await _writeNewJson(storage, contentPath, _contentToJson(tree));
    } else {
      tree = _contentFromJson(await _readJson(storage, contentPath));
    }
    await _addRegistration(
      storage,
      NovelRegistration(id: metadata.id, relativePath: root.value),
    );
    final snapshot = NovelSnapshot(
      rootPath: root.value,
      metadata: metadata,
      contentTree: tree,
    );
    return NovelStructureMutation(
      snapshot: snapshot,
      entry: _novelEntry(snapshot),
    );
  }

  @override
  Future<NovelStructureMutation> renameNovel(
    LibraryAccess access, {
    required NovelId novelId,
    required String newName,
  }) async {
    final storage = await storageFactory.open(access);
    final snapshot = await _loadNovel(
      storage,
      await _registration(storage, novelId),
    );
    final target = LogicalPath.parse(_validName(newName));
    await storage.move(LogicalPath.parse(snapshot.rootPath), target);
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
    await _replaceRegistration(storage, novelId, target.value);
    final updated = NovelSnapshot(
      rootPath: target.value,
      metadata: metadata,
      contentTree: snapshot.contentTree,
    );
    return NovelStructureMutation(
      snapshot: updated,
      entry: _novelEntry(updated),
      pathChanges: [
        PathChange(oldPath: snapshot.rootPath, newPath: target.value),
      ],
    );
  }

  @override
  Future<NovelStructureMutation> renameBody(
    LibraryAccess access, {
    required NovelId novelId,
    required String newName,
  }) async {
    final storage = await storageFactory.open(access);
    final snapshot = await _loadNovel(
      storage,
      await _registration(storage, novelId),
    );
    final root = LogicalPath.parse(snapshot.rootPath);
    final oldBody = snapshot.metadata.body.relativePath;
    final valid = _validName(newName);
    await storage.move(root.child(oldBody), root.child(valid));
    final metadata = _copyNovel(
      snapshot.metadata,
      revision: snapshot.metadata.revision + 1,
      body: NovelBody(id: snapshot.metadata.body.id, relativePath: valid),
      updatedAt: clock.nowUtc(),
    );
    final nodes = snapshot.contentTree.nodes
        .map(
          (node) => node.copyWith(
            relativePath:
                '$valid/${node.relativePath.substring(oldBody.length + 1)}',
          ),
        )
        .toList(growable: false);
    final tree = ContentTree(
      schemaVersion: 2,
      novelId: novelId,
      revision: snapshot.contentTree.revision + 1,
      nodes: nodes,
    );
    await _writeNovelSnapshot(storage, snapshot.rootPath, metadata, tree);
    final updated = NovelSnapshot(
      rootPath: snapshot.rootPath,
      metadata: metadata,
      contentTree: tree,
    );
    return NovelStructureMutation(
      snapshot: updated,
      entry: _bodyEntry(updated),
      pathChanges: [
        PathChange(
          oldPath: '${snapshot.rootPath}/$oldBody',
          newPath: '${snapshot.rootPath}/$valid',
        ),
      ],
    );
  }

  @override
  Future<NovelStructureMutation> createVolume(
    LibraryAccess access, {
    required NovelId novelId,
  }) async {
    final storage = await storageFactory.open(access);
    final snapshot = await _loadNovel(
      storage,
      await _registration(storage, novelId),
    );
    final volumes = snapshot.contentTree.nodes.where(
      (node) => node.type == ContentNodeType.volume,
    );
    var number = _maxNumber(volumes) + 1;
    LogicalPath target;
    do {
      target = LogicalPath.parse(
        '${snapshot.rootPath}/${snapshot.metadata.body.relativePath}/第$number卷',
      );
      number += 1;
    } while (await storage.stat(target) != null);
    await storage.createDirectory(target);
    final node = ContentNode(
      id: ContentId(idGenerator.generate()),
      type: ContentNodeType.volume,
      parentId: snapshot.metadata.body.id,
      relativePath: target.value.substring(snapshot.rootPath.length + 1),
      order: _nextOrder(
        snapshot.contentTree.childrenOf(snapshot.metadata.body.id),
      ),
      number: number - 1,
      role: ContentRole.normal,
    );
    return _commitNodes(storage, snapshot, [
      ...snapshot.contentTree.nodes,
      node,
    ], node);
  }

  @override
  Future<NovelStructureMutation> createChapter(
    LibraryAccess access, {
    required NovelId novelId,
    ContentId? volumeId,
  }) async {
    final storage = await storageFactory.open(access);
    final snapshot = await _loadNovel(
      storage,
      await _registration(storage, novelId),
    );
    final volume = volumeId == null
        ? null
        : snapshot.contentTree.nodeById(volumeId);
    if (volumeId != null && volume?.type != ContentNodeType.volume) {
      throw _invalid('章节只能创建在正文或卷中。');
    }
    final parentId = volumeId ?? snapshot.metadata.body.id;
    final parentPath =
        volume?.relativePath ?? snapshot.metadata.body.relativePath;
    final candidates =
        snapshot.metadata.numberingMode == NumberingMode.continuous
        ? snapshot.contentTree.nodes.where(
            (node) => node.type == ContentNodeType.chapter,
          )
        : snapshot.contentTree.childrenOf(parentId);
    var number = _maxNumber(candidates) + 1;
    final extension = snapshot.metadata.chapterFormat == ChapterFormat.text
        ? '.txt'
        : '.md';
    LogicalPath target;
    do {
      target = LogicalPath.parse(
        '${snapshot.rootPath}/$parentPath/第$number章$extension',
      );
      number += 1;
    } while (await storage.stat(target) != null);
    await storage.createFile(target, Uint8List(0));
    final node = ContentNode(
      id: ContentId(idGenerator.generate()),
      type: ContentNodeType.chapter,
      parentId: parentId,
      relativePath: target.value.substring(snapshot.rootPath.length + 1),
      order: _nextOrder(snapshot.contentTree.childrenOf(parentId)),
      number: number - 1,
      role: ContentRole.normal,
    );
    return _commitNodes(storage, snapshot, [
      ...snapshot.contentTree.nodes,
      node,
    ], node);
  }

  @override
  Future<NovelStructureMutation> renameNode(
    LibraryAccess access, {
    required NovelId novelId,
    required ContentId nodeId,
    required String newName,
  }) async {
    final storage = await storageFactory.open(access);
    final snapshot = await _loadNovel(
      storage,
      await _registration(storage, novelId),
    );
    final node = snapshot.contentTree.nodeById(nodeId);
    if (node == null) throw _notFound();
    var valid = _validName(newName);
    if (node.type == ContentNodeType.chapter) {
      final extension = _extension(node.relativePath);
      if (!_extension(valid).toLowerCase().endsWith(extension.toLowerCase())) {
        valid = '$valid$extension';
      }
    }
    final oldPath = LogicalPath.parse(
      '${snapshot.rootPath}/${node.relativePath}',
    );
    final newPath = oldPath.parent!.child(valid);
    await storage.move(oldPath, newPath);
    final oldRelative = node.relativePath;
    final newRelative = newPath.value.substring(snapshot.rootPath.length + 1);
    final nodes = snapshot.contentTree.nodes
        .map((candidate) {
          if (candidate.id == nodeId) {
            return candidate.copyWith(relativePath: newRelative);
          }
          if (node.type == ContentNodeType.volume &&
              candidate.relativePath.startsWith('$oldRelative/')) {
            return candidate.copyWith(
              relativePath:
                  '$newRelative/${candidate.relativePath.substring(oldRelative.length + 1)}',
            );
          }
          return candidate;
        })
        .toList(growable: false);
    final updatedNode = nodes.firstWhere((candidate) => candidate.id == nodeId);
    final mutation = await _commitNodes(storage, snapshot, nodes, updatedNode);
    return NovelStructureMutation(
      snapshot: mutation.snapshot,
      entry: mutation.entry,
      pathChanges: [PathChange(oldPath: oldPath.value, newPath: newPath.value)],
    );
  }

  @override
  Future<NovelStructureMutation> moveChapter(
    LibraryAccess access, {
    required NovelId novelId,
    required ContentId chapterId,
    ContentId? volumeId,
  }) async {
    final storage = await storageFactory.open(access);
    final snapshot = await _loadNovel(
      storage,
      await _registration(storage, novelId),
    );
    final chapter = snapshot.contentTree.nodeById(chapterId);
    final volume = volumeId == null
        ? null
        : snapshot.contentTree.nodeById(volumeId);
    if (chapter?.type != ContentNodeType.chapter ||
        (volumeId != null && volume?.type != ContentNodeType.volume)) {
      throw _invalid('章节或目标卷无效。');
    }
    final parentId = volumeId ?? snapshot.metadata.body.id;
    final parentPath =
        volume?.relativePath ?? snapshot.metadata.body.relativePath;
    final oldPath = LogicalPath.parse(
      '${snapshot.rootPath}/${chapter!.relativePath}',
    );
    final newPath = LogicalPath.parse(
      '${snapshot.rootPath}/$parentPath/${oldPath.name}',
    );
    await storage.move(oldPath, newPath);
    final moved = chapter.copyWith(
      parentId: parentId,
      relativePath: newPath.value.substring(snapshot.rootPath.length + 1),
      order: _nextOrder(snapshot.contentTree.childrenOf(parentId)),
    );
    final nodes = snapshot.contentTree.nodes
        .map((node) => node.id == chapterId ? moved : node)
        .toList();
    final mutation = await _commitNodes(storage, snapshot, nodes, moved);
    return NovelStructureMutation(
      snapshot: mutation.snapshot,
      entry: mutation.entry,
      pathChanges: [PathChange(oldPath: oldPath.value, newPath: newPath.value)],
    );
  }

  @override
  Future<NovelStructureMutation> reorderNode(
    LibraryAccess access, {
    required NovelId novelId,
    required ContentId nodeId,
    required int newIndex,
  }) async {
    final storage = await storageFactory.open(access);
    final snapshot = await _loadNovel(
      storage,
      await _registration(storage, novelId),
    );
    final nodes = ContentTreeRules.reorder(
      snapshot.contentTree,
      nodeId: nodeId,
      newIndex: newIndex,
    );
    return _commitNodes(
      storage,
      snapshot,
      nodes,
      nodes.firstWhere((node) => node.id == nodeId),
    );
  }

  @override
  Future<NovelReconciliationResult> reconcile(
    LibraryAccess access, {
    required NovelId novelId,
  }) async {
    final storage = await storageFactory.open(access);
    final snapshot = await _loadNovel(
      storage,
      await _registration(storage, novelId),
    );
    final scanned = await _scanTree(
      storage,
      LogicalPath.parse(snapshot.rootPath),
      snapshot.metadata,
      snapshot.contentTree.nodes,
      revision: snapshot.contentTree.revision + 1,
    );
    if (_contentSignature(scanned.nodes) ==
        _contentSignature(snapshot.contentTree.nodes)) {
      return NovelReconciliationResult(snapshot: snapshot);
    }
    await _replaceJson(
      storage,
      LogicalPath.parse('${snapshot.rootPath}/.lore/content.json'),
      _contentToJson(scanned),
    );
    return NovelReconciliationResult(
      snapshot: NovelSnapshot(
        rootPath: snapshot.rootPath,
        metadata: snapshot.metadata,
        contentTree: scanned,
      ),
    );
  }

  @override
  Future<DeletionResult> deleteNode(
    LibraryAccess access, {
    required NovelId novelId,
    required ContentId nodeId,
  }) async {
    final storage = await storageFactory.open(access);
    final snapshot = await _loadNovel(
      storage,
      await _registration(storage, novelId),
    );
    final target = snapshot.contentTree.nodeById(nodeId);
    if (target == null) throw _notFound();
    final subtree = snapshot.contentTree.nodes
        .where(
          (node) =>
              node.id == nodeId ||
              node.relativePath.startsWith('${target.relativePath}/'),
        )
        .toList();
    final token = idGenerator.generate();
    final source = LogicalPath.parse(
      '${snapshot.rootPath}/${target.relativePath}',
    );
    final trashPath = _trashTarget(token, source);
    await _ensureTrash(storage, token);
    final record = _TrashRecord(
      pending: true,
      item: TrashItem(
        token: token,
        type: target.type == ContentNodeType.volume
            ? TrashItemType.volume
            : TrashItemType.chapter,
        originalRelativePath: source.value,
        trashRelativePath: trashPath.value,
        novelId: novelId.value,
        nodeId: nodeId.value,
        novelRootPath: snapshot.rootPath,
        deletedAt: clock.nowUtc(),
        restorable: true,
      ),
      nodes: subtree,
    );
    await _appendTrash(storage, record);
    try {
      await _ensureTrashParents(storage, token, source);
      await storage.move(source, trashPath);
    } on Object {
      await _removeTrashRecord(storage, token);
      rethrow;
    }
    await _markTrashCommitted(storage, token);
    final tree = ContentTree(
      schemaVersion: 2,
      novelId: novelId,
      revision: snapshot.contentTree.revision + 1,
      nodes: snapshot.contentTree.nodes
          .where((node) => !subtree.contains(node))
          .toList(),
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
    return DeletionResult(
      snapshot: updated,
      trashToken: token,
      removedNodeIds: subtree.map((node) => node.id).toList(),
      pathChanges: [
        PathChange(oldPath: source.value, newPath: trashPath.value),
      ],
    );
  }

  @override
  Future<DeletionResult> deleteNovel(
    LibraryAccess access, {
    required NovelId novelId,
  }) async {
    final storage = await storageFactory.open(access);
    final registration = await _registration(storage, novelId);
    final source = LogicalPath.parse(registration.relativePath);
    final token = idGenerator.generate();
    final target = _trashTarget(token, source);
    await _ensureTrash(storage, token);
    final record = _TrashRecord(
      pending: true,
      item: TrashItem(
        token: token,
        type: TrashItemType.novel,
        originalRelativePath: source.value,
        trashRelativePath: target.value,
        novelId: novelId.value,
        novelRootPath: source.value,
        deletedAt: clock.nowUtc(),
        restorable: true,
      ),
    );
    await _appendTrash(storage, record);
    try {
      await _ensureTrashParents(storage, token, source);
      await storage.move(source, target);
    } on Object {
      await _removeTrashRecord(storage, token);
      rethrow;
    }
    await _markTrashCommitted(storage, token);
    await _removeRegistration(storage, novelId);
    return DeletionResult(
      trashToken: token,
      removedNodeIds: const [],
      pathChanges: [PathChange(oldPath: source.value, newPath: target.value)],
    );
  }

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
    } else if (record.nodes.isNotEmpty && record.item.novelId != null) {
      final registration = await _registration(
        storage,
        NovelId(record.item.novelId!),
      );
      final snapshot = await _loadNovel(storage, registration);
      final restoredNodes = record.nodes
          .map((node) {
            final originalNodePath = LogicalPath.parse(
              '${snapshot.rootPath}/${node.relativePath}',
            );
            if (originalNodePath ==
                    LogicalPath.parse(record.item.originalRelativePath) ||
                LogicalPath.parse(
                  record.item.originalRelativePath,
                ).contains(originalNodePath)) {
              final suffix = originalNodePath.value.substring(
                record.item.originalRelativePath.length,
              );
              return node.copyWith(
                relativePath: '${target.value}$suffix'.substring(
                  snapshot.rootPath.length + 1,
                ),
              );
            }
            return node;
          })
          .toList(growable: false);
      final restoredIds = restoredNodes.map((node) => node.id).toSet();
      final tree = ContentTree(
        schemaVersion: 2,
        novelId: snapshot.metadata.id,
        revision: snapshot.contentTree.revision + 1,
        nodes: [
          ...snapshot.contentTree.nodes.where(
            (node) => !restoredIds.contains(node.id),
          ),
          ...restoredNodes,
        ],
      );
      await _replaceJson(
        storage,
        LogicalPath.parse('${snapshot.rootPath}/.lore/content.json'),
        _contentToJson(tree),
      );
    }
    records.removeAt(index);
    await _writeTrashRecords(storage, records);
    return _copyTrashItem(record.item, originalPath: target.value);
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

  Future<ContentTree> _scanTree(
    LibraryStorageSession storage,
    LogicalPath novelRoot,
    NovelMetadata metadata,
    List<ContentNode> existing, {
    required int revision,
  }) async {
    final existingByPath = {
      for (final node in existing) node.relativePath: node,
    };
    final nodes = <ContentNode>[];
    final body = novelRoot.child(metadata.body.relativePath);
    final bodyEntries = await storage.list(body)
      ..sort((left, right) => left.path.name.compareTo(right.path.name));
    var rootOrder = _nextOrder(
      existing
          .where((node) => node.parentId == metadata.body.id)
          .toList(growable: false),
    );
    for (final entry in bodyEntries) {
      final relative = entry.path.value.substring(novelRoot.value.length + 1);
      if (entry.type == StorageEntryType.directory) {
        final volume =
            existingByPath[relative] ??
            ContentNode(
              id: ContentId(idGenerator.generate()),
              type: ContentNodeType.volume,
              parentId: metadata.body.id,
              relativePath: relative,
              order: rootOrder,
              number:
                  nodes
                      .where((node) => node.type == ContentNodeType.volume)
                      .length +
                  1,
              role: ContentRole.normal,
            );
        nodes.add(volume);
        var childOrder = _nextOrder(
          existing
              .where((node) => node.parentId == volume.id)
              .toList(growable: false),
        );
        final children = await storage.list(entry.path)
          ..sort((left, right) => left.path.name.compareTo(right.path.name));
        for (final child in children) {
          if (child.type == StorageEntryType.file &&
              _documentFormat(child.path.name) != null) {
            final childRelative = child.path.value.substring(
              novelRoot.value.length + 1,
            );
            final chapter =
                existingByPath[childRelative] ??
                ContentNode(
                  id: ContentId(idGenerator.generate()),
                  type: ContentNodeType.chapter,
                  parentId: volume.id,
                  relativePath: childRelative,
                  order: childOrder,
                  number: childOrder ~/ 1000,
                  role: ContentRole.normal,
                );
            nodes.add(chapter.copyWith(parentId: volume.id));
            if (!existingByPath.containsKey(childRelative)) {
              childOrder += 1000;
            }
          }
        }
      } else if (_documentFormat(entry.path.name) != null) {
        final chapter =
            existingByPath[relative] ??
            ContentNode(
              id: ContentId(idGenerator.generate()),
              type: ContentNodeType.chapter,
              parentId: metadata.body.id,
              relativePath: relative,
              order: rootOrder,
              number:
                  nodes
                      .where((node) => node.type == ContentNodeType.chapter)
                      .length +
                  1,
              role: ContentRole.normal,
            );
        nodes.add(chapter.copyWith(parentId: metadata.body.id));
      }
      if (!existingByPath.containsKey(relative)) {
        rootOrder += 1000;
      }
    }
    return ContentTree(
      schemaVersion: 2,
      novelId: metadata.id,
      revision: revision,
      nodes: nodes,
    );
  }

  Future<NovelSnapshot> _loadNovel(
    LibraryStorageSession storage,
    NovelRegistration registration,
  ) async {
    final metadataRoot = LogicalPath.parse(
      '${registration.relativePath}/.lore',
    );
    final metadata = _novelFromJson(
      await _readJson(storage, metadataRoot.child('novel.json')),
    );
    final tree = _contentFromJson(
      await _readJson(storage, metadataRoot.child('content.json')),
    );
    if (metadata.id != registration.id || tree.novelId != metadata.id) {
      throw _invalid('书库注册信息与小说元数据不一致。');
    }
    return NovelSnapshot(
      rootPath: registration.relativePath,
      metadata: metadata,
      contentTree: tree,
    );
  }

  Future<void> _writeNovelSnapshot(
    LibraryStorageSession storage,
    String rootPath,
    NovelMetadata metadata,
    ContentTree tree,
  ) async {
    final root = LogicalPath.parse('$rootPath/.lore');
    await _replaceJson(
      storage,
      root.child('novel.json'),
      _novelToJson(metadata),
    );
    await _replaceJson(
      storage,
      root.child('content.json'),
      _contentToJson(tree),
    );
  }

  Future<Map<String, Object?>> _readJson(
    LibraryStorageSession storage,
    LogicalPath path,
  ) async {
    final value = jsonDecode(utf8.decode(await storage.readBytes(path)));
    if (value is! Map<String, Object?>) throw const FormatException();
    return value;
  }

  Future<void> _writeNewJson(
    LibraryStorageSession storage,
    LogicalPath path,
    Map<String, Object?> value,
  ) {
    return storage.createFile(
      path,
      Uint8List.fromList(utf8.encode(_encode(value))),
    );
  }

  Future<void> _replaceJson(
    LibraryStorageSession storage,
    LogicalPath path,
    Map<String, Object?> value,
  ) async {
    final current = await storage.stat(path);
    if (current?.revision == null) throw _notFound();
    final result = await storage.replaceFile(
      path,
      expectedRevision: current!.revision!,
      bytes: Uint8List.fromList(utf8.encode(_encode(value))),
    );
    if (result is StorageReplaceConflict) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.externalModification,
          message: '元数据已在外部修改，请重新加载书库。',
        ),
      );
    }
  }

  String _encode(Map<String, Object?> value) =>
      '${const JsonEncoder.withIndent('  ').convert(value)}\n';

  LibraryMetadata _libraryFromJson(Map<String, Object?> value) =>
      LibraryMetadata(
        schemaVersion: 2,
        revision: value['revision']! as int,
        id: LibraryId(value['libraryId']! as String),
        createdAt: DateTime.parse(value['createdAt']! as String).toUtc(),
        updatedAt: DateTime.parse(value['updatedAt']! as String).toUtc(),
        novels: _registrations(value),
      );

  Map<String, Object?> _libraryToJson(LibraryMetadata value) => {
    'schemaVersion': 2,
    'revision': value.revision,
    'libraryId': value.id.value,
    'createdAt': value.createdAt.toUtc().toIso8601String(),
    'updatedAt': value.updatedAt.toUtc().toIso8601String(),
    'novels': value.novels
        .map((item) => {'id': item.id.value, 'path': item.relativePath})
        .toList(),
    'templates': <Object?>[],
  };

  NovelMetadata _novelFromJson(Map<String, Object?> value) {
    final body = value['body']! as Map<String, Object?>;
    return NovelMetadata(
      schemaVersion: 2,
      revision: value['revision']! as int,
      id: NovelId(value['novelId']! as String),
      title: value['title']! as String,
      description: value['description']! as String,
      coverPath: value['cover'] as String?,
      body: NovelBody(
        id: ContentId(body['id']! as String),
        relativePath: body['path']! as String,
      ),
      chapterFormat: value['chapterFormat'] == 'text'
          ? ChapterFormat.text
          : ChapterFormat.markdown,
      numberingMode: value['numberingMode'] == 'perVolume'
          ? NumberingMode.perVolume
          : NumberingMode.continuous,
      createdAt: DateTime.parse(value['createdAt']! as String).toUtc(),
      updatedAt: DateTime.parse(value['updatedAt']! as String).toUtc(),
    );
  }

  Map<String, Object?> _novelToJson(NovelMetadata value) => {
    'schemaVersion': 2,
    'revision': value.revision,
    'novelId': value.id.value,
    'title': value.title,
    'description': value.description,
    'cover': value.coverPath,
    'body': {'id': value.body.id.value, 'path': value.body.relativePath},
    'chapterFormat': value.chapterFormat.name,
    'numberingMode': value.numberingMode.name,
    'createdAt': value.createdAt.toUtc().toIso8601String(),
    'updatedAt': value.updatedAt.toUtc().toIso8601String(),
  };

  ContentTree _contentFromJson(Map<String, Object?> value) => ContentTree(
    schemaVersion: 2,
    novelId: NovelId(value['novelId']! as String),
    revision: value['revision']! as int,
    nodes: (value['nodes']! as List<Object?>).map((raw) {
      final item = raw! as Map<String, Object?>;
      return ContentNode(
        id: ContentId(item['id']! as String),
        type: item['type'] == 'volume'
            ? ContentNodeType.volume
            : ContentNodeType.chapter,
        parentId: ContentId(item['parentId']! as String),
        relativePath: item['path']! as String,
        order: item['order']! as int,
        number: item['number'] as int?,
        role: ContentRole.values.byName(item['role']! as String),
      );
    }).toList(),
  );

  Map<String, Object?> _contentToJson(ContentTree value) => {
    'schemaVersion': 2,
    'novelId': value.novelId.value,
    'revision': value.revision,
    'nodes': value.nodes
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

  List<NovelRegistration> _registrations(Map<String, Object?> library) {
    return (library['novels']! as List<Object?>).map((raw) {
      final item = raw! as Map<String, Object?>;
      return NovelRegistration(
        id: NovelId(item['id']! as String),
        relativePath: item['path']! as String,
      );
    }).toList();
  }

  Future<NovelRegistration> _registration(
    LibraryStorageSession storage,
    NovelId id,
  ) async {
    final registrations = _registrations(
      await _readJson(storage, _libraryManifest),
    );
    return registrations.firstWhere(
      (item) => item.id == id,
      orElse: () => throw _notFound(),
    );
  }

  Future<void> _addRegistration(
    LibraryStorageSession storage,
    NovelRegistration registration,
  ) async {
    final library = await _readJson(storage, _libraryManifest);
    final registrations = _registrations(library);
    if (!registrations.any((item) => item.id == registration.id)) {
      registrations.add(registration);
    }
    await _saveRegistrations(storage, library, registrations);
  }

  Future<void> _replaceRegistration(
    LibraryStorageSession storage,
    NovelId id,
    String path,
  ) async {
    final library = await _readJson(storage, _libraryManifest);
    final registrations = _registrations(library);
    final index = registrations.indexWhere((item) => item.id == id);
    if (index < 0) throw _notFound();
    registrations[index] = NovelRegistration(id: id, relativePath: path);
    await _saveRegistrations(storage, library, registrations);
  }

  Future<void> _removeRegistration(
    LibraryStorageSession storage,
    NovelId id,
  ) async {
    final library = await _readJson(storage, _libraryManifest);
    final registrations = _registrations(library)
      ..removeWhere((item) => item.id == id);
    await _saveRegistrations(storage, library, registrations);
  }

  Future<void> _saveRegistrations(
    LibraryStorageSession storage,
    Map<String, Object?> library,
    List<NovelRegistration> registrations,
  ) async {
    library['revision'] = (library['revision'] as int) + 1;
    library['updatedAt'] = clock.nowUtc().toIso8601String();
    library['novels'] = registrations
        .map((item) => {'id': item.id.value, 'path': item.relativePath})
        .toList();
    await _replaceJson(storage, _libraryManifest, library);
  }

  NovelMetadata _copyNovel(
    NovelMetadata value, {
    required int revision,
    String? title,
    NovelBody? body,
    DateTime? updatedAt,
  }) => NovelMetadata(
    schemaVersion: 2,
    revision: revision,
    id: value.id,
    title: title ?? value.title,
    description: value.description,
    coverPath: value.coverPath,
    body: body ?? value.body,
    chapterFormat: value.chapterFormat,
    numberingMode: value.numberingMode,
    createdAt: value.createdAt,
    updatedAt: updatedAt ?? value.updatedAt,
  );

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
    if (await storage.stat(_trashManifest) == null) return [];
    final value = await _readJson(storage, _trashManifest);
    final records = (value['items'] as List<Object?>? ?? const [])
        .map((raw) => _TrashRecord.fromJson(raw! as Map<String, Object?>))
        .toList();
    var changed = false;
    for (final record in List<_TrashRecord>.of(records)) {
      final trashExists =
          await storage.stat(
            LogicalPath.parse(record.item.trashRelativePath),
          ) !=
          null;
      if (record.pending && trashExists) {
        final index = records.indexOf(record);
        records[index] = record.copyWith(pending: false);
        changed = true;
      } else if (!trashExists) {
        records.remove(record);
        changed = true;
      }
    }
    if (changed) {
      await _writeTrashRecords(storage, records);
    }
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
    if (index < 0) {
      throw _notFound();
    }
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

  LibraryEntry _annotateEntry(LibraryEntry entry, List<NovelSnapshot> novels) {
    for (final novel in novels) {
      if (entry.relativePath == novel.rootPath) {
        return _novelEntry(novel);
      }
      if (entry.relativePath ==
          '${novel.rootPath}/${novel.metadata.body.relativePath}') {
        return _bodyEntry(novel);
      }
      for (final node in novel.contentTree.nodes) {
        if (entry.relativePath == '${novel.rootPath}/${node.relativePath}') {
          return _contentEntry(novel, node);
        }
      }
    }
    return entry;
  }

  LibraryEntry _novelEntry(NovelSnapshot snapshot) => LibraryEntry(
    name: snapshot.rootPath.split('/').last,
    relativePath: snapshot.rootPath,
    type: LibraryEntryType.directory,
    semanticKind: LibraryEntrySemanticKind.novel,
    semanticId: snapshot.metadata.id.value,
    novelId: snapshot.metadata.id.value,
  );

  LibraryEntry _bodyEntry(NovelSnapshot snapshot) => LibraryEntry(
    name: snapshot.metadata.body.relativePath.split('/').last,
    relativePath: '${snapshot.rootPath}/${snapshot.metadata.body.relativePath}',
    type: LibraryEntryType.directory,
    semanticKind: LibraryEntrySemanticKind.body,
    semanticId: snapshot.metadata.body.id.value,
    novelId: snapshot.metadata.id.value,
  );

  LibraryEntry _contentEntry(NovelSnapshot snapshot, ContentNode node) =>
      LibraryEntry(
        name: node.relativePath.split('/').last,
        relativePath: '${snapshot.rootPath}/${node.relativePath}',
        type: node.type == ContentNodeType.volume
            ? LibraryEntryType.directory
            : _libraryFileType(node.relativePath),
        semanticKind: node.type == ContentNodeType.volume
            ? LibraryEntrySemanticKind.volume
            : LibraryEntrySemanticKind.chapter,
        semanticId: node.id.value,
        novelId: snapshot.metadata.id.value,
        semanticOrder: node.order,
      );

  LibraryEntry _entry(LogicalPath path, StorageEntryType type) => LibraryEntry(
    name: path.name,
    relativePath: path.value,
    type: type == StorageEntryType.directory
        ? LibraryEntryType.directory
        : _libraryFileType(path.name),
  );

  LibraryEntryType _entryType(StorageEntry entry) =>
      entry.type == StorageEntryType.directory
      ? LibraryEntryType.directory
      : _libraryFileType(entry.path.name);

  LibraryEntryType _libraryFileType(String name) =>
      switch (_extension(name).toLowerCase()) {
        '.txt' => LibraryEntryType.textFile,
        '.md' => LibraryEntryType.markdownFile,
        _ => LibraryEntryType.otherFile,
      };

  DocumentFormat? _documentFormat(String name) =>
      switch (_extension(name).toLowerCase()) {
        '.txt' => DocumentFormat.text,
        '.md' => DocumentFormat.markdown,
        _ => null,
      };

  LogicalPath _child(String parentPath, String name) =>
      LogicalPath.parse(parentPath).child(name);
  String _extension(String name) {
    final index = name.lastIndexOf('.');
    return index <= 0 ? '' : name.substring(index);
  }

  String _validName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty ||
        trimmed.startsWith('.') ||
        trimmed.contains('/') ||
        trimmed.contains(r'\')) {
      throw _invalid('名称无效。');
    }
    return trimmed;
  }

  int _maxNumber(Iterable<ContentNode> nodes) => nodes.fold(
    0,
    (value, node) =>
        node.number != null && node.number! > value ? node.number! : value,
  );
  int _nextOrder(List<ContentNode> nodes) => nodes.isEmpty
      ? 1000
      : nodes.map((node) => node.order).reduce((a, b) => a > b ? a : b) + 1000;
  String _contentSignature(List<ContentNode> nodes) {
    final signatures =
        nodes
            .map(
              (node) =>
                  '${node.id.value}:${node.parentId.value}:${node.relativePath}:${node.order}',
            )
            .toList()
          ..sort();
    return signatures.join('|');
  }

  LineEnding _lineEnding(String text) {
    final crlf = RegExp(r'\r\n').allMatches(text).length;
    final lf = RegExp(r'(?<!\r)\n').allMatches(text).length;
    if (crlf > 0 && lf > 0) return LineEnding.mixed;
    return crlf > 0 ? LineEnding.crlf : LineEnding.lf;
  }

  String _applyLineEnding(String text, LineEnding ending) =>
      ending == LineEnding.crlf
      ? text.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n')
      : text;

  LibraryOperationException _invalid(String message) =>
      LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.invalidLocation,
          message: message,
        ),
      );

  LibraryOperationException _notFound() => const LibraryOperationException(
    LibraryFailure(code: LibraryFailureCode.notFound, message: '文件或目录不存在。'),
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
    return _TrashRecord(
      pending: value['pending'] == true,
      item: TrashItem(
        token: value['token']! as String,
        type: TrashItemType.values.byName(value['type']! as String),
        originalRelativePath: value['originalPath']! as String,
        trashRelativePath: value['trashPath']! as String,
        deletedAt: DateTime.parse(value['deletedAt']! as String).toUtc(),
        restorable: true,
        novelId: value['novelId'] as String?,
        nodeId: value['nodeId'] as String?,
        novelRootPath: value['novelRootPath'] as String?,
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
