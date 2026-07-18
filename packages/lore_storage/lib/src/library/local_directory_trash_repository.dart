import 'dart:io';

import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:path/path.dart' as p;

import 'internal/content_tree_scanner.dart';
import 'internal/library_path_resolver.dart';
import 'internal/library_paths.dart';
import 'internal/library_storage_io.dart';
import 'internal/novel_manifest_codec.dart';
import 'internal/pending_operation_journal.dart';
import 'internal/trash_internals.dart';

/// [TrashRepository] 端口适配器：listItems / restore / purge / empty。
final class LocalDirectoryTrashRepository implements TrashRepository {
  LocalDirectoryTrashRepository({
    required this.paths,
    required this.resolver,
    required this.io,
    required this.novels,
    required this.scanner,
    required this.pending,
    required this.trash,
  });

  final LibraryPaths paths;
  final LibraryPathResolver resolver;
  final LibraryStorageIo io;
  final NovelManifestCodec novels;
  final ContentTreeScanner scanner;
  final PendingOperationJournal pending;
  final TrashInternals trash;

  @override
  Future<List<TrashItem>> listItems(LibraryAccess access) async {
    final rootPath = await resolver.resolveRoot(access);
    return trash.readTrashManifestWithReconcile(rootPath);
  }

  @override
  Future<TrashItem> restore(
    LibraryAccess access, {
    required String trashToken,
    RestoreConflictStrategy strategy = RestoreConflictStrategy.rename,
  }) async {
    final rootPath = await resolver.resolveRoot(access);
    final items = await trash.readTrashManifest(rootPath);
    final index = items.indexWhere((item) => item.token == trashToken);
    if (index < 0) {
      throw const LibraryOperationException(
        LibraryFailure(code: LibraryFailureCode.notFound, message: '回收站条目不存在。'),
      );
    }
    final item = items[index];
    final novelId = item.novelId == null ? null : NovelId(item.novelId!);

    await pending.writePending(
      rootPath,
      novelId ?? const NovelId('00000000-0000-4000-8000-000000000000'),
      item.novelRootPath ?? '',
      operation: 'restoreItem',
      sourcePath: item.trashRelativePath,
      targetPath: item.originalRelativePath,
    );
    try {
      await _restoreItemFiles(rootPath, item, strategy);
      await trash.removeTrashManifestItem(rootPath, trashToken);
      await io.deleteDirectorySafely(
        paths.trashTokenRoot(rootPath, trashToken),
        recursive: true,
      );
      // 重建内容树节点身份：让 reconcile 重新发现移回的文件。
      if (novelId != null && item.novelRootPath != null) {
        await _reconcileAfterRestore(rootPath, novelId, item.novelRootPath!);
      }
      // 恢复整本小说时，把它重新登记回书库 manifest（deleteNovel 已移除登记）。
      if (item.type == TrashItemType.novel &&
          novelId != null &&
          item.novelRootPath != null) {
        await novels.registerNovel(rootPath, novelId, item.novelRootPath!);
      }
      await pending.clearPending(rootPath);
    } on LibraryOperationException {
      await pending.clearPending(rootPath);
      rethrow;
    } on FileSystemException catch (error) {
      await pending.clearPending(rootPath);
      throw LibraryOperationException(io.fileSystemFailure(error));
    }
    return item;
  }

  Future<List<String>> _restoreItemFiles(
    String rootPath,
    TrashItem item,
    RestoreConflictStrategy strategy,
  ) async {
    final restored = <String>[];
    final novelId = item.novelId == null ? null : NovelId(item.novelId!);

    Future<String> resolveTarget(String original) async {
      final candidate = p.join(rootPath, original);
      if (!await FileSystemEntity.type(
        candidate,
        followLinks: false,
      ).then((t) => t == FileSystemEntityType.notFound)) {
        switch (strategy) {
          case RestoreConflictStrategy.skip:
            return candidate;
          case RestoreConflictStrategy.overwrite:
            await io.deletePathSafelyRecursive(candidate);
            return candidate;
          case RestoreConflictStrategy.rename:
            return trash.nextAvailablePath(rootPath, original);
        }
      }
      return candidate;
    }

    Future<void> moveOne(String trashRelative, String original) async {
      final source = p.join(rootPath, trashRelative);
      final target = await resolveTarget(original);
      await Directory(p.dirname(target)).create(recursive: true);
      final type = await FileSystemEntity.type(source, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        await Directory(source).rename(target);
      } else if (type == FileSystemEntityType.file) {
        await File(source).rename(target);
      }
      restored.add(target);
    }

    // 卷：先移卷目录（含章节），子项随目录一起恢复；章节单删则逐个移回。
    if (item.type == TrashItemType.volume) {
      await moveOne(item.trashRelativePath, item.originalRelativePath);
    } else {
      await moveOne(item.trashRelativePath, item.originalRelativePath);
      for (final child in item.children) {
        await moveOne(child.trashRelativePath, child.originalRelativePath);
      }
    }
    // novel 删除时整目录已移走，恢复移回整目录即可；entry 同理。
    if (novelId != null) {
      // no-op: novel/entry handled by single move above
    }
    return restored;
  }

  Future<void> _reconcileAfterRestore(
    String rootPath,
    NovelId novelId,
    String novelRootPath,
  ) async {
    try {
      final novelRoot = p.join(rootPath, novelRootPath);
      final contentFile = File(paths.contentManifestPath(novelRoot));
      if (!await contentFile.exists()) {
        return;
      }
      final snapshot = await novels.loadNovel(
        rootPath,
        NovelRegistration(id: novelId, relativePath: novelRootPath),
      );
      final scanned = await scanner.scanContentTree(
        novelRoot,
        snapshot.metadata,
        snapshot.contentTree.nodes,
      );
      await io.writeJsonAtomic(contentFile, novels.contentToJson(scanned));
    } on LibraryOperationException {
      // 恢复后协调失败不阻断恢复本身；watcher 会再次触发 reconcile。
    }
  }

  @override
  Future<void> purge(LibraryAccess access, {required String trashToken}) async {
    final rootPath = await resolver.resolveRoot(access);
    await trash.removeTrashManifestItem(rootPath, trashToken);
    await io.deleteDirectorySafely(
      paths.trashTokenRoot(rootPath, trashToken),
      recursive: true,
    );
  }

  @override
  Future<void> empty(LibraryAccess access) async {
    final rootPath = await resolver.resolveRoot(access);
    await io.deleteDirectorySafely(paths.trashRoot(rootPath), recursive: true);
  }
}
