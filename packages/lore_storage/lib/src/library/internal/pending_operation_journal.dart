import 'dart:io';

import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:path/path.dart' as p;

import 'content_tree_scanner.dart';
import 'library_paths.dart';
import 'library_storage_io.dart';
import 'novel_manifest_codec.dart';

/// 结构操作（rename/move/create/trash/restore）的崩溃恢复日志。
///
/// 方法按原 [LocalDirectoryLibraryRepository] 中的实现逐字搬迁。
/// 注意：原实现的 [_recoverPending] 中关于「trash/restore 操作的 novelPath
/// 可能为空」的不变量注释已在此保留。
final class PendingOperationJournal {
  PendingOperationJournal({
    required this.paths,
    required this.io,
    required this.novels,
    required this.scanner,
    required this.clock,
  });

  final LibraryPaths paths;
  final LibraryStorageIo io;
  final NovelManifestCodec novels;
  final ContentTreeScanner scanner;
  final Clock clock;

  Future<void> writePending(
    String rootPath,
    NovelId novelId,
    String novelPath, {
    required String operation,
    String? sourcePath,
    String? targetPath,
  }) async {
    final file = File(paths.pendingPath(rootPath));
    await file.parent.create(recursive: true);
    if (await file.exists()) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.externalModification,
          message: '存在尚未恢复的结构操作，请重新打开书库。',
        ),
      );
    }
    await io.writeJsonNew(file, {
      'schemaVersion': LibraryPaths.schemaVersion,
      'novelId': novelId.value,
      'novelPath': novelPath,
      'operation': operation,
      'sourcePath': sourcePath,
      'targetPath': targetPath,
      'startedAt': clock.nowUtc().toIso8601String(),
    });
  }

  Future<void> clearPending(String rootPath) {
    return io.deleteFileSafely(paths.pendingPath(rootPath));
  }

  Future<void> recoverPending(String rootPath) async {
    final pendingFile = File(paths.pendingPath(rootPath));
    if (!await pendingFile.exists()) {
      return;
    }
    final pending = await io.readJsonObject(pendingFile);
    final novelIdValue = pending['novelId'];
    final novelPath = pending['novelPath'];
    final operation = pending['operation'];
    final sourcePath = pending['sourcePath'];
    final targetPath = pending['targetPath'];
    // trash/restore 操作的 novelPath 可能为空（删除/恢复普通文件、恢复孤儿），
    // 它们的崩溃恢复不依赖小说 manifest：直接 clearPending，让 watcher、
    // trash 目录对账（listItems）与下次 reconcile 把状态收敛到一致。
    final isTrashOperation =
        operation == 'trashNode' ||
        operation == 'trashNovel' ||
        operation == 'trashEntry' ||
        operation == 'restoreItem';
    if (novelIdValue is! String ||
        !io.isUuid(novelIdValue) ||
        novelPath is! String ||
        (!isTrashOperation && !paths.isMetadataRelativePath(novelPath)) ||
        operation is! String ||
        (sourcePath != null && sourcePath is! String) ||
        (sourcePath != null &&
            !paths.isMetadataRelativePath(sourcePath as String)) ||
        (targetPath != null && targetPath is! String) ||
        (targetPath != null &&
            !paths.isMetadataRelativePath(targetPath as String))) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.metadataCorrupt,
          message: '结构操作恢复记录已损坏。',
        ),
      );
    }
    if (isTrashOperation) {
      await clearPending(rootPath);
      return;
    }
    final novelRoot = p.join(rootPath, novelPath);
    if (!await Directory(novelRoot).exists()) {
      await clearPending(rootPath);
      return;
    }
    final novelFile = File(paths.novelManifestPath(novelRoot));
    if (!await novelFile.exists()) {
      await clearPending(rootPath);
      return;
    }
    var metadata = novels.parseNovelMetadata(
      await io.readJsonObject(novelFile),
    );
    if (metadata.id.value != novelIdValue) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.metadataCorrupt,
          message: '恢复记录与小说元数据不一致。',
        ),
      );
    }
    if (operation == 'renameNovel' &&
        sourcePath is String &&
        targetPath is String &&
        !await Directory(p.join(rootPath, sourcePath)).exists() &&
        await Directory(p.join(rootPath, targetPath)).exists() &&
        metadata.title != p.basename(targetPath)) {
      metadata = NovelMetadata(
        schemaVersion: metadata.schemaVersion,
        id: metadata.id,
        title: p.basename(targetPath),
        description: metadata.description,
        coverPath: metadata.coverPath,
        body: metadata.body,
        chapterFormat: metadata.chapterFormat,
        numberingMode: metadata.numberingMode,
        createdAt: metadata.createdAt,
        updatedAt: clock.nowUtc(),
      );
      await io.writeJsonAtomic(novelFile, novels.novelToJson(metadata));
    }
    final contentFile = File(paths.contentManifestPath(novelRoot));
    var existing = await contentFile.exists()
        ? novels.parseContentTree(await io.readJsonObject(contentFile)).nodes
        : const <ContentNode>[];
    if (operation == 'renameBody' &&
        sourcePath is String &&
        targetPath is String) {
      final oldBody = p.relative(sourcePath, from: novelPath);
      final newBody = p.relative(targetPath, from: novelPath);
      if (metadata.body.relativePath == oldBody &&
          !await Directory(p.join(rootPath, sourcePath)).exists() &&
          await Directory(p.join(rootPath, targetPath)).exists()) {
        metadata = NovelMetadata(
          schemaVersion: metadata.schemaVersion,
          id: metadata.id,
          title: metadata.title,
          description: metadata.description,
          coverPath: metadata.coverPath,
          body: NovelBody(id: metadata.body.id, relativePath: newBody),
          chapterFormat: metadata.chapterFormat,
          numberingMode: metadata.numberingMode,
          createdAt: metadata.createdAt,
          updatedAt: clock.nowUtc(),
        );
        existing = existing
            .map(
              (node) => node.copyWith(
                relativePath: p.join(
                  newBody,
                  p.relative(node.relativePath, from: oldBody),
                ),
              ),
            )
            .toList(growable: false);
        await io.writeJsonAtomic(novelFile, novels.novelToJson(metadata));
      }
    }
    if ((operation == 'renameNode' || operation == 'moveChapter') &&
        sourcePath is String &&
        targetPath is String &&
        await FileSystemEntity.type(
              p.join(rootPath, sourcePath),
              followLinks: false,
            ) ==
            FileSystemEntityType.notFound &&
        await FileSystemEntity.type(
              p.join(rootPath, targetPath),
              followLinks: false,
            ) !=
            FileSystemEntityType.notFound) {
      final oldRelative = p.relative(sourcePath, from: novelPath);
      final newRelative = p.relative(targetPath, from: novelPath);
      final targetParentPath = p.dirname(newRelative);
      final targetParent = targetParentPath == metadata.body.relativePath
          ? metadata.body.id
          : existing
                .where(
                  (node) =>
                      node.type == ContentNodeType.volume &&
                      node.relativePath == targetParentPath,
                )
                .firstOrNull
                ?.id;
      existing = existing
          .map((node) {
            if (node.relativePath == oldRelative) {
              return node.copyWith(
                parentId: targetParent ?? node.parentId,
                relativePath: newRelative,
              );
            }
            if (p.isWithin(oldRelative, node.relativePath)) {
              return node.copyWith(
                relativePath: p.join(
                  newRelative,
                  p.relative(node.relativePath, from: oldRelative),
                ),
              );
            }
            return node;
          })
          .toList(growable: false);
    }
    final scanned = await scanner.scanContentTree(
      novelRoot,
      metadata,
      existing,
    );
    await io.writeJsonAtomic(contentFile, novels.contentToJson(scanned));
    final manifest = await io.readJsonObject(
      File(paths.manifestPath(rootPath)),
    );
    final registrations = novels.parseNovelRegistrations(manifest['novels']);
    if (registrations.any((registration) => registration.id == metadata.id)) {
      await novels.updateNovelRegistration(rootPath, metadata.id, novelPath);
    } else {
      await novels.registerNovel(rootPath, metadata.id, novelPath);
    }
    await clearPending(rootPath);
  }
}
