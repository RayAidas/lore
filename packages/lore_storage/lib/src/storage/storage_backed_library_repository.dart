import 'dart:convert';
import 'dart:typed_data';

import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';

import 'storage_schema_migrator.dart';

part 'portable/storage_backed_library_support.dart';
part 'portable/storage_backed_document_repository.dart';
part 'portable/storage_backed_trash_support.dart';
part 'portable/storage_backed_trash_repository.dart';

final _metadata = LogicalPath.parse('.lore');
final _recoveryRoot = LogicalPath.parse('.lore/recovery');
final _libraryManifest = LogicalPath.parse('.lore/library.json');
final _trashRoot = LogicalPath.parse('.lore/trash');
final _trashManifest = LogicalPath.parse('.lore/trash/index.json');
final _pendingOperation = LogicalPath.parse(
  '.lore/recovery/pending-operation.json',
);

/// Portable semantic repository used by non-path storage backends such as SAF.
final class StorageBackedLibraryRepository
    with
        _StorageBackedLibrarySupport,
        _StorageBackedDocumentRepository,
        _StorageBackedTrashSupport,
        _StorageBackedTrashRepository
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

  @override
  final LibraryStorageFactory storageFactory;
  @override
  final IdGenerator idGenerator;
  @override
  final Clock clock;

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
      await _recoverPendingMutation(storage);
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
    } on TypeError {
      return const LibraryInspectionFailure(
        LibraryFailure(
          code: LibraryFailureCode.metadataCorrupt,
          message: '书库元数据无效。',
        ),
      );
    } on ArgumentError {
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
    if (await storage.stat(_recoveryRoot) == null) {
      await storage.createDirectory(_recoveryRoot);
    }
    final now = clock.nowUtc();
    final metadata = LibraryMetadata(
      schemaVersion: 2,
      revision: 0,
      id: LibraryId(idGenerator.generate()),
      createdAt: now,
      updatedAt: now,
    );
    try {
      await _writeNewJson(storage, _libraryManifest, _libraryToJson(metadata));
    } on LibraryOperationException catch (error) {
      if (error.failure.code != LibraryFailureCode.alreadyExists) {
        rethrow;
      }
      final raced = await inspect(access);
      if (raced case LibraryInspectionReady(:final metadata)) {
        return metadata;
      }
      if (raced case LibraryInspectionFailure(:final failure)) {
        throw LibraryOperationException(failure);
      }
      rethrow;
    }
    return metadata;
  }

  @override
  Future<List<LibraryEntry>> listChildren(
    LibraryAccess access, {
    String relativePath = '',
  }) async {
    final storage = await storageFactory.open(access);
    final directory = _publicPath(relativePath);
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
    final novels = await storage.stat(_libraryManifest) == null
        ? const <NovelSnapshot>[]
        : await listNovels(access);
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
    final target = _publicPath(parentPath).child(_validName(name));
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
    final target = _publicPath(parentPath).child(fileName);
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
    final source = _publicPath(relativePath);
    final sourceEntry = await storage.stat(source);
    if (sourceEntry == null) {
      throw _notFound();
    }
    var valid = _validName(newName);
    if (sourceEntry.type == StorageEntryType.file) {
      final extension = _extension(source.name);
      final requestedExtension = _extension(valid);
      if (requestedExtension.isNotEmpty &&
          requestedExtension.toLowerCase() != extension.toLowerCase()) {
        throw _invalidName('不能更改文档扩展名。');
      }
      if (extension.isNotEmpty && requestedExtension.isEmpty) {
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
    final source = _publicPath(relativePath);
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
  Future<List<NovelSnapshot>> listNovels(LibraryAccess access) async {
    final storage = await storageFactory.open(access);
    final library = await _readJson(storage, _libraryManifest);
    final result = <NovelSnapshot>[];
    for (final registration in _registrations(library)) {
      try {
        result.add(await _loadNovel(storage, registration));
      } on LibraryOperationException catch (error) {
        if (error.failure.code != LibraryFailureCode.notFound) rethrow;
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
    final root = _publicPath(relativePath);
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
    await _beginMutation(
      storage,
      operation: 'renameNovel',
      novelId: novelId,
      novelPath: snapshot.rootPath,
      source: LogicalPath.parse(snapshot.rootPath),
      target: target,
    );
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
    await _clearPendingMutation(storage);
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
    await _beginMutation(
      storage,
      operation: 'renameBody',
      novelId: novelId,
      novelPath: snapshot.rootPath,
      source: root.child(oldBody),
      target: root.child(valid),
    );
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
    await _clearPendingMutation(storage);
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
      final requestedExtension = _extension(valid);
      if (requestedExtension.isNotEmpty &&
          requestedExtension.toLowerCase() != extension.toLowerCase()) {
        throw _invalidName('不能更改章节扩展名。');
      }
      if (requestedExtension.isEmpty) {
        valid = '$valid$extension';
      }
    }
    final oldPath = LogicalPath.parse(
      '${snapshot.rootPath}/${node.relativePath}',
    );
    final newPath = oldPath.parent!.child(valid);
    await _beginMutation(
      storage,
      operation: 'renameNode',
      novelId: novelId,
      novelPath: snapshot.rootPath,
      source: oldPath,
      target: newPath,
    );
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
    await _clearPendingMutation(storage);
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
    await _beginMutation(
      storage,
      operation: 'moveChapter',
      novelId: novelId,
      novelPath: snapshot.rootPath,
      source: oldPath,
      target: newPath,
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
    await _clearPendingMutation(storage);
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
}
