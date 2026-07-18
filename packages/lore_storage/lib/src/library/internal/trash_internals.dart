import 'dart:io';

import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:path/path.dart' as p;

import 'library_paths.dart';
import 'library_storage_io.dart';

/// 回收站的底层文件操作与 manifest 维护。
///
/// 不包含 [TrashRepository] 的对外 API（restore/purge/empty 等），
/// 仅提供被 trash 适配器与 deleteEntry/deleteNode/deleteNovel 复用的原语。
/// 方法按原 [LocalDirectoryLibraryRepository] 中的实现逐字搬迁。
final class TrashInternals {
  TrashInternals({required this.paths, required this.io, required this.clock});

  final LibraryPaths paths;
  final LibraryStorageIo io;
  final Clock clock;

  Future<void> ensureTrashRoot(String rootPath) async {
    try {
      await Directory(paths.trashRoot(rootPath)).create(recursive: true);
    } on FileSystemException catch (error) {
      throw LibraryOperationException(io.fileSystemFailure(error));
    }
  }

  Future<List<TrashItem>> readTrashManifest(String rootPath) async {
    final file = File(paths.trashManifestPath(rootPath));
    if (!await file.exists()) {
      return const [];
    }
    try {
      final value = await io.readJsonObject(file);
      final items = value['items'];
      if (items is! List<Object?>) {
        return const [];
      }
      return items.map(parseTrashItem).whereType<TrashItem>().toList();
    } on LibraryOperationException {
      return const [];
    }
  }

  /// 读 manifest 并对账文件系统：扫描 `.lore/trash/` 下未被 manifest 记录的
  /// token 目录（崩溃在移动后、写清单前留下的孤儿），补录为可恢复条目，
  /// 使其可见、可恢复或可 purge。
  Future<List<TrashItem>> readTrashManifestWithReconcile(
    String rootPath,
  ) async {
    final trashRoot = Directory(paths.trashRoot(rootPath));
    if (!await trashRoot.exists()) {
      return const [];
    }
    final manifestItems = List<TrashItem>.from(
      await readTrashManifest(rootPath),
    );
    final knownTokens = manifestItems.map((item) => item.token).toSet();
    final subEntities = await trashRoot.list(followLinks: false).toList();
    var changed = false;
    for (final entity in subEntities) {
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type != FileSystemEntityType.directory) {
        continue;
      }
      final token = p.basename(entity.path);
      if (knownTokens.contains(token)) {
        continue;
      }
      manifestItems.add(await orphanTrashItem(rootPath, token));
      changed = true;
    }
    if (changed) {
      await writeTrashManifest(rootPath, manifestItems);
    }
    return manifestItems;
  }

  /// 为孤儿 token 目录生成一个 TrashItem：把目录下第一层条目作为原相对路径，
  /// 按文件移回（无法可靠推断 novel/volume/chapter 语义，因此标记为 entry）。
  Future<TrashItem> orphanTrashItem(String rootPath, String token) async {
    final tokenRoot = paths.trashTokenRoot(rootPath, token);
    var original = '(未知)';
    await for (final entity in Directory(tokenRoot).list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (name.startsWith('.')) {
        continue;
      }
      original = p.relative(entity.path, from: tokenRoot);
      break;
    }
    return TrashItem(
      token: token,
      type: TrashItemType.entry,
      originalRelativePath: original,
      trashRelativePath: p.relative(tokenRoot, from: rootPath),
      deletedAt: clock.nowUtc(),
      restorable: original != '(未知)',
    );
  }

  Future<void> writeTrashManifest(
    String rootPath,
    List<TrashItem> items,
  ) async {
    await ensureTrashRoot(rootPath);
    final encoded = {
      'schemaVersion': LibraryPaths.schemaVersion,
      'items': items.map(trashItemToJson).toList(),
    };
    await io.writeJsonAtomic(File(paths.trashManifestPath(rootPath)), encoded);
  }

  Future<void> appendTrashManifest(String rootPath, TrashItem item) async {
    final items = List<TrashItem>.from(await readTrashManifest(rootPath));
    items.add(item);
    await writeTrashManifest(rootPath, items);
  }

  Future<void> removeTrashManifestItem(String rootPath, String token) async {
    final items = await readTrashManifest(rootPath);
    items.removeWhere((item) => item.token == token);
    await writeTrashManifest(rootPath, items);
  }

  TrashItem? parseTrashItem(Object? value) {
    if (value is! Map<String, Object?>) {
      return null;
    }
    final token = value['token'];
    final typeString = value['type'];
    final original = value['originalRelativePath'];
    final trash = value['trashRelativePath'];
    final deletedAt = value['deletedAt'];
    final restorable = value['restorable'];
    if (token is! String ||
        original is! String ||
        trash is! String ||
        deletedAt is! String ||
        restorable is! bool) {
      return null;
    }
    final type = switch (typeString) {
      'novel' => TrashItemType.novel,
      'volume' => TrashItemType.volume,
      'chapter' => TrashItemType.chapter,
      'entry' => TrashItemType.entry,
      _ => null,
    };
    if (type == null) {
      return null;
    }
    final parsedTime = DateTime.tryParse(deletedAt);
    if (parsedTime == null) {
      return null;
    }
    final childrenRaw = value['children'];
    final children = <TrashItemChild>[];
    if (childrenRaw is List<Object?>) {
      for (final raw in childrenRaw) {
        if (raw is! Map<String, Object?>) {
          continue;
        }
        final childNodeId = raw['nodeId'];
        final childOriginal = raw['originalRelativePath'];
        final childTrash = raw['trashRelativePath'];
        if (childNodeId is String &&
            childOriginal is String &&
            childTrash is String) {
          children.add(
            TrashItemChild(
              nodeId: childNodeId,
              originalRelativePath: childOriginal,
              trashRelativePath: childTrash,
            ),
          );
        }
      }
    }
    return TrashItem(
      token: token,
      type: type,
      originalRelativePath: original,
      trashRelativePath: trash,
      novelId: value['novelId'] as String?,
      nodeId: value['nodeId'] as String?,
      novelRootPath: value['novelRootPath'] as String?,
      deletedAt: parsedTime.toUtc(),
      restorable: restorable,
      children: children,
    );
  }

  Map<String, Object?> trashItemToJson(TrashItem item) => {
    'token': item.token,
    'type': item.type.name,
    'originalRelativePath': item.originalRelativePath,
    'trashRelativePath': item.trashRelativePath,
    'novelId': item.novelId,
    'nodeId': item.nodeId,
    'novelRootPath': item.novelRootPath,
    'deletedAt': item.deletedAt.toUtc().toIso8601String(),
    'restorable': item.restorable,
    'children': item.children
        .map(
          (child) => {
            'nodeId': child.nodeId,
            'originalRelativePath': child.originalRelativePath,
            'trashRelativePath': child.trashRelativePath,
          },
        )
        .toList(),
  };

  /// 收集 [nodeId] 及其子树（卷下全部章节）。
  List<ContentNode> collectSubtree(ContentTree tree, ContentId nodeId) {
    final root = tree.nodeById(nodeId);
    if (root == null) {
      return const [];
    }
    final result = <ContentNode>[root];
    if (root.type == ContentNodeType.volume) {
      for (final node in tree.nodes) {
        if (node.parentId == root.id) {
          result.add(node);
        }
      }
    }
    return result;
  }

  Future<void> moveIntoTrash(
    String rootPath,
    String token,
    String originalRelativePath,
  ) async {
    final source = p.join(rootPath, originalRelativePath);
    final target = paths.resolveTrashTarget(
      rootPath,
      token,
      originalRelativePath,
    );
    await Directory(p.dirname(target)).create(recursive: true);
    final type = await FileSystemEntity.type(source, followLinks: false);
    try {
      if (type == FileSystemEntityType.directory) {
        await Directory(source).rename(target);
      } else {
        await File(source).rename(target);
      }
    } on FileSystemException catch (error) {
      throw LibraryOperationException(io.fileSystemFailure(error));
    }
  }

  String nextAvailablePath(String rootPath, String original) {
    var counter = 1;
    final dir = p.dirname(original);
    final base = p.basenameWithoutExtension(original);
    final ext = p.extension(original);
    while (true) {
      final candidate = p.join(rootPath, dir, '$base (恢复 $counter)$ext');
      // 同步检查存在性：restore 是异步上下文，此处用阻塞占位路径生成，
      // 真正的冲突由调用前的 FileSystemEntity.type 判断；此处仅生成名字。
      final placeholder = File(candidate);
      if (!placeholder.existsSync()) {
        return candidate;
      }
      counter += 1;
    }
  }
}
