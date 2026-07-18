import 'dart:io';

import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:path/path.dart' as p;

import 'internal/content_tree_scanner.dart';
import 'internal/library_entry_utils.dart';
import 'internal/library_path_resolver.dart';
import 'internal/library_paths.dart';
import 'internal/library_storage_io.dart';
import 'internal/novel_manifest_codec.dart';
import 'internal/pending_operation_journal.dart';
import 'internal/trash_internals.dart';

/// [ContentTreeRepository] 端口适配器：卷 / 章节的增、改、删、排序、对账。
/// deleteNode 会把节点（卷含其下章节）移入回收站。
final class LocalDirectoryContentTreeRepository
    implements ContentTreeRepository {
  LocalDirectoryContentTreeRepository({
    required this.idGenerator,
    required this.clock,
    required this.gateway,
    required this.paths,
    required this.resolver,
    required this.io,
    required this.entries,
    required this.novels,
    required this.scanner,
    required this.pending,
    required this.trash,
  });

  final IdGenerator idGenerator;
  final Clock clock;
  final LibraryFileOperationsGateway? gateway;
  final LibraryPaths paths;
  final LibraryPathResolver resolver;
  final LibraryStorageIo io;
  final LibraryEntryUtils entries;
  final NovelManifestCodec novels;
  final ContentTreeScanner scanner;
  final PendingOperationJournal pending;
  final TrashInternals trash;

  @override
  Future<NovelStructureMutation> createVolume(
    LibraryAccess access, {
    required NovelId novelId,
  }) async {
    final rootPath = await resolver.resolveRoot(access);
    final snapshot = await novels.loadNovel(
      rootPath,
      await novels.registrationFor(rootPath, novelId),
    );
    var number =
        scanner.maximumNumber(
          snapshot.contentTree.nodes.where(
            (node) => node.type == ContentNodeType.volume,
          ),
        ) +
        1;
    late String name;
    late String targetPath;
    do {
      name = '第${scanner.chineseNumber(number)}卷';
      targetPath = p.join(
        rootPath,
        snapshot.rootPath,
        snapshot.metadata.body.relativePath,
        name,
      );
      number += 1;
    } while (await FileSystemEntity.type(targetPath, followLinks: false) !=
        FileSystemEntityType.notFound);
    final node = ContentNode(
      id: ContentId(idGenerator.generate()),
      type: ContentNodeType.volume,
      parentId: snapshot.metadata.body.id,
      relativePath: p.join(snapshot.metadata.body.relativePath, name),
      order: scanner.nextOrder(
        snapshot.contentTree.childrenOf(snapshot.metadata.body.id),
      ),
      number: number - 1,
      role: ContentRole.normal,
    );
    return _createContentEntity(
      access,
      rootPath,
      snapshot,
      node,
      isDirectory: true,
    );
  }

  @override
  Future<NovelStructureMutation> createChapter(
    LibraryAccess access, {
    required NovelId novelId,
    ContentId? volumeId,
  }) async {
    final rootPath = await resolver.resolveRoot(access);
    final snapshot = await novels.loadNovel(
      rootPath,
      await novels.registrationFor(rootPath, novelId),
    );
    final volume = volumeId == null
        ? null
        : snapshot.contentTree.nodeById(volumeId);
    if (volumeId != null && volume?.type != ContentNodeType.volume) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.invalidLocation,
          message: '章节只能创建在正文或卷中。',
        ),
      );
    }
    final parentId = volumeId ?? snapshot.metadata.body.id;
    final parentPath =
        volume?.relativePath ?? snapshot.metadata.body.relativePath;
    final candidates =
        snapshot.metadata.numberingMode == NumberingMode.continuous
        ? snapshot.contentTree.nodes.where(
            (node) => node.type == ContentNodeType.chapter,
          )
        : snapshot.contentTree
              .childrenOf(parentId)
              .where((node) => node.type == ContentNodeType.chapter);
    var number = scanner.maximumNumber(candidates) + 1;
    final extension = snapshot.metadata.chapterFormat == ChapterFormat.text
        ? '.txt'
        : '.md';
    late String name;
    late String targetPath;
    do {
      name = '第$number章$extension';
      targetPath = p.join(rootPath, snapshot.rootPath, parentPath, name);
      number += 1;
    } while (await FileSystemEntity.type(targetPath, followLinks: false) !=
        FileSystemEntityType.notFound);
    final node = ContentNode(
      id: ContentId(idGenerator.generate()),
      type: ContentNodeType.chapter,
      parentId: parentId,
      relativePath: p.join(parentPath, name),
      order: scanner.nextOrder(snapshot.contentTree.childrenOf(parentId)),
      number: number - 1,
      role: ContentRole.normal,
    );
    return _createContentEntity(
      access,
      rootPath,
      snapshot,
      node,
      isDirectory: false,
    );
  }

  @override
  Future<NovelStructureMutation> renameNode(
    LibraryAccess access, {
    required NovelId novelId,
    required ContentId nodeId,
    required String newName,
  }) async {
    final rootPath = await resolver.resolveRoot(access);
    final snapshot = await novels.loadNovel(
      rootPath,
      await novels.registrationFor(rootPath, novelId),
    );
    final node = snapshot.contentTree.nodeById(nodeId);
    if (node == null) {
      throw const LibraryOperationException(
        LibraryFailure(code: LibraryFailureCode.notFound, message: '卷或章节不存在。'),
      );
    }
    final sourcePath = p.join(rootPath, snapshot.rootPath, node.relativePath);
    final currentName = p.basename(sourcePath);
    final validName = node.type == ContentNodeType.chapter
        ? entries.renamedDocumentName(currentName, newName)
        : entries.validateName(newName);
    if (validName == currentName) {
      return NovelStructureMutation(
        snapshot: snapshot,
        entry: _entryForContent(snapshot, node),
      );
    }
    final targetPath = p.join(p.dirname(sourcePath), validName);
    if (await FileSystemEntity.type(targetPath, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw io.alreadyExists(validName);
    }
    await pending.writePending(
      rootPath,
      novelId,
      snapshot.rootPath,
      operation: 'renameNode',
      sourcePath: p.join(snapshot.rootPath, node.relativePath),
      targetPath: p.relative(targetPath, from: rootPath),
    );
    await entries.renameEntity(
      access,
      gateway,
      rootPath,
      sourcePath,
      targetPath,
      node.type == ContentNodeType.volume
          ? FileSystemEntityType.directory
          : FileSystemEntityType.file,
    );
    final oldRelative = node.relativePath;
    final newRelative = p.join(p.dirname(oldRelative), validName);
    final nodes = snapshot.contentTree.nodes
        .map((candidate) {
          if (candidate.id == node.id) {
            return candidate.copyWith(relativePath: newRelative);
          }
          if (node.type == ContentNodeType.volume &&
              p.isWithin(oldRelative, candidate.relativePath)) {
            return candidate.copyWith(
              relativePath: p.join(
                newRelative,
                p.relative(candidate.relativePath, from: oldRelative),
              ),
            );
          }
          return candidate;
        })
        .toList(growable: false);
    final updated = await _writeContentTree(rootPath, snapshot, nodes);
    await pending.clearPending(rootPath);
    final libraryOld = p.join(snapshot.rootPath, oldRelative);
    final libraryNew = p.join(snapshot.rootPath, newRelative);
    return NovelStructureMutation(
      snapshot: updated,
      entry: _entryForContent(updated, updated.contentTree.nodeById(node.id)!),
      pathChanges: [PathChange(oldPath: libraryOld, newPath: libraryNew)],
    );
  }

  @override
  Future<NovelStructureMutation> moveChapter(
    LibraryAccess access, {
    required NovelId novelId,
    required ContentId chapterId,
    ContentId? volumeId,
  }) async {
    final rootPath = await resolver.resolveRoot(access);
    final snapshot = await novels.loadNovel(
      rootPath,
      await novels.registrationFor(rootPath, novelId),
    );
    final chapter = snapshot.contentTree.nodeById(chapterId);
    final volume = volumeId == null
        ? null
        : snapshot.contentTree.nodeById(volumeId);
    if (chapter?.type != ContentNodeType.chapter ||
        (volumeId != null && volume?.type != ContentNodeType.volume)) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.invalidLocation,
          message: '章节或目标卷无效。',
        ),
      );
    }
    final parentId = volumeId ?? snapshot.metadata.body.id;
    if (chapter!.parentId == parentId) {
      return NovelStructureMutation(
        snapshot: snapshot,
        entry: _entryForContent(snapshot, chapter),
      );
    }
    final parentPath =
        volume?.relativePath ?? snapshot.metadata.body.relativePath;
    final newRelative = p.join(parentPath, p.basename(chapter.relativePath));
    final oldLibraryPath = p.join(snapshot.rootPath, chapter.relativePath);
    final newLibraryPath = p.join(snapshot.rootPath, newRelative);
    if (await FileSystemEntity.type(
          p.join(rootPath, newLibraryPath),
          followLinks: false,
        ) !=
        FileSystemEntityType.notFound) {
      throw io.alreadyExists(p.basename(newRelative));
    }
    await pending.writePending(
      rootPath,
      novelId,
      snapshot.rootPath,
      operation: 'moveChapter',
      sourcePath: oldLibraryPath,
      targetPath: newLibraryPath,
    );
    await entries.renameEntity(
      access,
      gateway,
      rootPath,
      p.join(rootPath, oldLibraryPath),
      p.join(rootPath, newLibraryPath),
      FileSystemEntityType.file,
    );
    final moved = chapter.copyWith(
      parentId: parentId,
      relativePath: newRelative,
      order: scanner.nextOrder(snapshot.contentTree.childrenOf(parentId)),
    );
    final nodes = snapshot.contentTree.nodes
        .map((node) => node.id == chapter.id ? moved : node)
        .toList(growable: false);
    final updated = await _writeContentTree(rootPath, snapshot, nodes);
    await pending.clearPending(rootPath);
    return NovelStructureMutation(
      snapshot: updated,
      entry: _entryForContent(updated, moved),
      pathChanges: [
        PathChange(oldPath: oldLibraryPath, newPath: newLibraryPath),
      ],
    );
  }

  @override
  Future<NovelStructureMutation> reorderNode(
    LibraryAccess access, {
    required NovelId novelId,
    required ContentId nodeId,
    required int newIndex,
  }) async {
    final rootPath = await resolver.resolveRoot(access);
    final snapshot = await novels.loadNovel(
      rootPath,
      await novels.registrationFor(rootPath, novelId),
    );
    final node = snapshot.contentTree.nodeById(nodeId);
    if (node == null) {
      throw const LibraryOperationException(
        LibraryFailure(code: LibraryFailureCode.notFound, message: '内容不存在。'),
      );
    }
    List<ContentNode> nodes;
    try {
      nodes = ContentTreeRules.reorder(
        snapshot.contentTree,
        nodeId: nodeId,
        newIndex: newIndex,
        orderStep: LibraryPaths.orderStep,
      );
    } on FormatException {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.invalidLocation,
          message: '排序位置无效。',
        ),
      );
    }
    await pending.writePending(
      rootPath,
      novelId,
      snapshot.rootPath,
      operation: 'reorderNode',
    );
    final updated = await _writeContentTree(rootPath, snapshot, nodes);
    await pending.clearPending(rootPath);
    return NovelStructureMutation(
      snapshot: updated,
      entry: _entryForContent(updated, updated.contentTree.nodeById(nodeId)!),
    );
  }

  @override
  Future<NovelReconciliationResult> reconcile(
    LibraryAccess access, {
    required NovelId novelId,
  }) async {
    final rootPath = await resolver.resolveRoot(access);
    final snapshot = await novels.loadNovel(
      rootPath,
      await novels.registrationFor(rootPath, novelId),
    );
    final novelRoot = p.join(rootPath, snapshot.rootPath);
    final scanned = await scanner.scanContentTree(
      novelRoot,
      snapshot.metadata,
      snapshot.contentTree.nodes,
    );
    final scannedPaths = scanned.nodes.map((node) => node.relativePath).toSet();
    final scannedIds = scanned.nodes.map((node) => node.id).toSet();
    final issues = snapshot.contentTree.nodes
        .where(
          (node) =>
              !scannedPaths.contains(node.relativePath) &&
              !scannedIds.contains(node.id),
        )
        .map(
          (node) => ReconciliationIssue(
            message: '卷章文件缺失，已保留原有身份信息。',
            relativePath: p.join(snapshot.rootPath, node.relativePath),
          ),
        )
        .toList(growable: false);
    final merged = <ContentNode>[
      ...scanned.nodes,
      ...snapshot.contentTree.nodes.where(
        (node) =>
            !scannedPaths.contains(node.relativePath) &&
            !scannedIds.contains(node.id),
      ),
    ];
    final changed =
        scanner.contentSignature(merged) !=
        scanner.contentSignature(snapshot.contentTree.nodes);
    final updated = changed
        ? await _writeContentTree(rootPath, snapshot, merged)
        : snapshot;
    return NovelReconciliationResult(snapshot: updated, issues: issues);
  }

  @override
  Future<DeletionResult> deleteNode(
    LibraryAccess access, {
    required NovelId novelId,
    required ContentId nodeId,
  }) async {
    final rootPath = await resolver.resolveRoot(access);
    final snapshot = await novels.loadNovel(
      rootPath,
      await novels.registrationFor(rootPath, novelId),
    );
    final subtree = trash.collectSubtree(snapshot.contentTree, nodeId);
    if (subtree.isEmpty) {
      throw const LibraryOperationException(
        LibraryFailure(code: LibraryFailureCode.notFound, message: '节点不存在。'),
      );
    }
    final target = subtree.first;
    final token = idGenerator.generate();
    final libraryNodePath = p.join(snapshot.rootPath, target.relativePath);

    await pending.writePending(
      rootPath,
      novelId,
      snapshot.rootPath,
      operation: 'trashNode',
      sourcePath: libraryNodePath,
      targetPath: p.join(
        LibraryPaths.metadataDirectoryName,
        LibraryPaths.trashDirectoryName,
        token,
        target.relativePath,
      ),
    );
    try {
      await trash.ensureTrashRoot(rootPath);
      // 只移根节点：卷目录会连带其下章节，避免逐个移动时子项已随目录移走。
      await trash.moveIntoTrash(
        rootPath,
        token,
        p.join(snapshot.rootPath, target.relativePath),
      );
      final remainingNodes = snapshot.contentTree.nodes
          .where((node) => !subtree.any((s) => s.id == node.id))
          .toList(growable: false);
      final updatedTree = ContentTree(
        schemaVersion: snapshot.contentTree.schemaVersion,
        novelId: snapshot.contentTree.novelId,
        revision: snapshot.contentTree.revision + 1,
        nodes: remainingNodes,
      );
      await io.writeJsonAtomic(
        File(paths.contentManifestPath(p.join(rootPath, snapshot.rootPath))),
        novels.contentToJson(updatedTree),
      );
      final children = subtree
          .where((node) => node.id != target.id)
          .map(
            (node) => TrashItemChild(
              nodeId: node.id.value,
              originalRelativePath: p.join(
                snapshot.rootPath,
                node.relativePath,
              ),
              trashRelativePath: paths
                  .resolveTrashTarget(
                    rootPath,
                    token,
                    p.join(snapshot.rootPath, node.relativePath),
                  )
                  .substring(rootPath.length + 1),
            ),
          )
          .toList();
      await trash.appendTrashManifest(
        rootPath,
        TrashItem(
          token: token,
          type: target.type == ContentNodeType.volume
              ? TrashItemType.volume
              : TrashItemType.chapter,
          originalRelativePath: libraryNodePath,
          trashRelativePath: paths
              .resolveTrashTarget(rootPath, token, libraryNodePath)
              .substring(rootPath.length + 1),
          novelId: novelId.value,
          nodeId: target.id.value,
          novelRootPath: snapshot.rootPath,
          deletedAt: clock.nowUtc(),
          restorable: true,
          children: children,
        ),
      );
      await pending.clearPending(rootPath);
    } on LibraryOperationException {
      await pending.clearPending(rootPath);
      rethrow;
    } on FileSystemException catch (error) {
      await pending.clearPending(rootPath);
      throw LibraryOperationException(io.fileSystemFailure(error));
    }

    final fresh = await novels.loadNovel(
      rootPath,
      await novels.registrationFor(rootPath, novelId),
    );
    return DeletionResult(
      snapshot: fresh,
      trashToken: token,
      removedNodeIds: subtree.map((node) => node.id).toList(),
      pathChanges: [
        PathChange(
          oldPath: libraryNodePath,
          newPath: p.join(
            LibraryPaths.metadataDirectoryName,
            LibraryPaths.trashDirectoryName,
            token,
            target.relativePath,
          ),
        ),
      ],
    );
  }

  LibraryEntry _entryForContent(NovelSnapshot snapshot, ContentNode node) {
    final libraryPath = p.join(snapshot.rootPath, node.relativePath);
    return entries.semanticEntry(
      name: p.basename(node.relativePath),
      relativePath: libraryPath,
      type: node.type == ContentNodeType.volume
          ? LibraryEntryType.directory
          : p.extension(node.relativePath).toLowerCase() == '.txt'
          ? LibraryEntryType.textFile
          : LibraryEntryType.markdownFile,
      kind: node.type == ContentNodeType.volume
          ? LibraryEntrySemanticKind.volume
          : LibraryEntrySemanticKind.chapter,
      semanticId: node.id.value,
      novelId: snapshot.metadata.id.value,
      semanticOrder: node.order,
    );
  }

  Future<NovelSnapshot> _writeContentTree(
    String rootPath,
    NovelSnapshot snapshot,
    List<ContentNode> nodes,
  ) async {
    final now = clock.nowUtc();
    final metadata = NovelMetadata(
      schemaVersion: snapshot.metadata.schemaVersion,
      revision: snapshot.metadata.revision + 1,
      id: snapshot.metadata.id,
      title: snapshot.metadata.title,
      description: snapshot.metadata.description,
      coverPath: snapshot.metadata.coverPath,
      body: snapshot.metadata.body,
      chapterFormat: snapshot.metadata.chapterFormat,
      numberingMode: snapshot.metadata.numberingMode,
      createdAt: snapshot.metadata.createdAt,
      updatedAt: now,
    );
    final tree = ContentTree(
      schemaVersion: snapshot.contentTree.schemaVersion,
      novelId: snapshot.contentTree.novelId,
      revision: snapshot.contentTree.revision + 1,
      nodes: nodes,
    );
    final novelRoot = p.join(rootPath, snapshot.rootPath);
    await io.writeJsonAtomic(
      File(paths.novelManifestPath(novelRoot)),
      novels.novelToJson(metadata),
    );
    await io.writeJsonAtomic(
      File(paths.contentManifestPath(novelRoot)),
      novels.contentToJson(tree),
    );
    return NovelSnapshot(
      rootPath: snapshot.rootPath,
      metadata: metadata,
      contentTree: tree,
    );
  }

  Future<NovelStructureMutation> _createContentEntity(
    LibraryAccess access,
    String rootPath,
    NovelSnapshot snapshot,
    ContentNode node, {
    required bool isDirectory,
  }) async {
    final libraryPath = p.join(snapshot.rootPath, node.relativePath);
    final parentPath = await resolver.resolveExistingDirectory(
      rootPath,
      p.dirname(libraryPath),
    );
    final entityPath = p.join(parentPath, p.basename(libraryPath));
    await pending.writePending(
      rootPath,
      snapshot.metadata.id,
      snapshot.rootPath,
      operation: isDirectory ? 'createVolume' : 'createChapter',
      targetPath: libraryPath,
    );
    var created = false;
    try {
      if (isDirectory) {
        await Directory(entityPath).create();
      } else {
        await File(entityPath).create(exclusive: true);
        await File(entityPath).writeAsString('', flush: true);
      }
      created = true;
      final updated = await _writeContentTree(rootPath, snapshot, [
        ...snapshot.contentTree.nodes,
        node,
      ]);
      await pending.clearPending(rootPath);
      return NovelStructureMutation(
        snapshot: updated,
        entry: _entryForContent(updated, node),
      );
    } catch (error) {
      if (created) {
        if (isDirectory) {
          await io.deleteDirectorySafely(entityPath);
        } else {
          await io.deleteFileSafely(entityPath);
        }
      }
      await pending.clearPending(rootPath);
      if (error is FileSystemException) {
        throw LibraryOperationException(io.fileSystemFailure(error));
      }
      rethrow;
    }
  }
}
