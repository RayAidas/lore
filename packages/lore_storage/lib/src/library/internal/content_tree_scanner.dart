import 'dart:io';

import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:path/path.dart' as p;

import 'library_paths.dart';

/// 从文件系统扫描小说正文目录并重建 [ContentTree]。
///
/// 方法按原 [LocalDirectoryLibraryRepository] 中的实现逐字搬迁。
final class ContentTreeScanner {
  ContentTreeScanner({required this.idGenerator, required this.paths});

  final IdGenerator idGenerator;
  final LibraryPaths paths;

  Future<ContentTree> scanContentTree(
    String novelRoot,
    NovelMetadata metadata,
    List<ContentNode> existing,
  ) async {
    final bodyRoot = p.join(novelRoot, metadata.body.relativePath);
    if (!await Directory(bodyRoot).exists()) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.notFound,
          message: '小说正文目录不存在。',
        ),
      );
    }
    final existingByPath = {
      for (final node in existing) node.relativePath: node,
    };
    final nextOrders = <ContentId, int>{};
    int takeOrder(ContentId parentId) {
      final next = nextOrders.putIfAbsent(parentId, () {
        return nextOrder(
          existing.where((node) => node.parentId == parentId).toList(),
        );
      });
      nextOrders[parentId] = next + LibraryPaths.orderStep;
      return next;
    }

    final nodes = <ContentNode>[];
    final matchedIds = <ContentId>{};

    Future<void> scanChapters(
      String directoryPath,
      ContentId parentId, {
      required String previousParentPath,
    }) async {
      final chapterPaths = <String>[];
      for (final entity in await visibleEntities(directoryPath)) {
        final type = await FileSystemEntity.type(
          entity.path,
          followLinks: false,
        );
        if (type == FileSystemEntityType.file &&
            isDocumentName(p.basename(entity.path))) {
          chapterPaths.add(p.relative(entity.path, from: novelRoot));
        }
      }

      final matches = <String, ContentNode>{};
      for (final relativePath in chapterPaths) {
        var candidate = existingByPath[relativePath];
        if (candidate?.type != ContentNodeType.chapter ||
            candidate?.parentId != parentId) {
          final previousPath = p.join(
            previousParentPath,
            p.basename(relativePath),
          );
          candidate = existingByPath[previousPath];
        }
        if (candidate?.type == ContentNodeType.chapter &&
            candidate?.parentId == parentId &&
            !matchedIds.contains(candidate!.id)) {
          matches[relativePath] = candidate;
          matchedIds.add(candidate.id);
        }
      }

      final unmatchedPaths = chapterPaths
          .where((path) => !matches.containsKey(path))
          .toList(growable: false);
      final missingChapters = existing
          .where(
            (node) =>
                node.type == ContentNodeType.chapter &&
                node.parentId == parentId &&
                !matchedIds.contains(node.id),
          )
          .toList(growable: false);
      if (unmatchedPaths.length == 1 && missingChapters.length == 1) {
        final renamed = missingChapters.single;
        matches[unmatchedPaths.single] = renamed;
        matchedIds.add(renamed.id);
      }

      for (final relativePath in chapterPaths) {
        final matched = matches[relativePath];
        nodes.add(
          matched != null
              ? matched.copyWith(parentId: parentId, relativePath: relativePath)
              : scannedChapter(relativePath, parentId, takeOrder(parentId)),
        );
      }
    }

    final volumeEntities = <FileSystemEntity>[];
    final rootChapterEntities = <FileSystemEntity>[];
    for (final entity in await visibleEntities(bodyRoot)) {
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        volumeEntities.add(entity);
      } else if (type == FileSystemEntityType.file &&
          isDocumentName(p.basename(entity.path))) {
        rootChapterEntities.add(entity);
      }
    }

    final detectedVolumePaths = volumeEntities
        .map((entity) => p.relative(entity.path, from: novelRoot))
        .toSet();
    final unmatchedVolumes = volumeEntities
        .where((entity) {
          final relativePath = p.relative(entity.path, from: novelRoot);
          return existingByPath[relativePath]?.type != ContentNodeType.volume;
        })
        .toList(growable: false);
    final missingVolumes = existing
        .where(
          (node) =>
              node.type == ContentNodeType.volume &&
              node.parentId == metadata.body.id &&
              !detectedVolumePaths.contains(node.relativePath),
        )
        .toList(growable: false);
    final renamedVolume =
        unmatchedVolumes.length == 1 && missingVolumes.length == 1
        ? missingVolumes.single
        : null;

    for (final entity in volumeEntities) {
      final relativePath = p.relative(entity.path, from: novelRoot);
      final existingVolume = existingByPath[relativePath];
      final matched = existingVolume?.type == ContentNodeType.volume
          ? existingVolume
          : renamedVolume;
      final previousPath = matched?.relativePath ?? relativePath;
      final volume = matched != null
          ? matched.copyWith(relativePath: relativePath)
          : ContentNode(
              id: ContentId(idGenerator.generate()),
              type: ContentNodeType.volume,
              parentId: metadata.body.id,
              relativePath: relativePath,
              order: takeOrder(metadata.body.id),
              number: volumeNumber(p.basename(entity.path)),
              role: ContentRole.normal,
            );
      matchedIds.add(volume.id);
      nodes.add(volume);
      await scanChapters(
        entity.path,
        volume.id,
        previousParentPath: previousPath,
      );
    }

    if (rootChapterEntities.isNotEmpty) {
      await scanChapters(
        bodyRoot,
        metadata.body.id,
        previousParentPath: metadata.body.relativePath,
      );
    }
    return ContentTree(
      schemaVersion: LibraryPaths.schemaVersion,
      novelId: metadata.id,
      revision: existing.isEmpty ? 0 : 1,
      nodes: nodes,
    );
  }

  Future<List<FileSystemEntity>> visibleEntities(String path) async {
    try {
      final entities = await Directory(path)
          .list(followLinks: false)
          .where((entity) => !p.basename(entity.path).startsWith('.'))
          .toList();
      entities.sort(
        (left, right) =>
            naturalCompare(p.basename(left.path), p.basename(right.path)),
      );
      return entities;
    } on FileSystemException catch (error) {
      throw LibraryOperationException(fileSystemFailure(error));
    }
  }

  ContentNode scannedChapter(
    String relativePath,
    ContentId parentId,
    int order,
  ) {
    final name = p.basenameWithoutExtension(relativePath);
    final role = name.startsWith('序章')
        ? ContentRole.prologue
        : name.startsWith('后记')
        ? ContentRole.epilogue
        : name.startsWith('番外')
        ? ContentRole.extra
        : ContentRole.normal;
    final match = RegExp(r'^第(\d+)章').firstMatch(name);
    return ContentNode(
      id: ContentId(idGenerator.generate()),
      type: ContentNodeType.chapter,
      parentId: parentId,
      relativePath: relativePath,
      order: order,
      number: match == null ? null : int.parse(match.group(1)!),
      role: role,
    );
  }

  int? volumeNumber(String name) {
    final arabic = RegExp(r'^第(\d+)卷').firstMatch(name);
    if (arabic != null) {
      return int.parse(arabic.group(1)!);
    }
    final chinese = RegExp(r'^第([零一二三四五六七八九十百千]+)卷').firstMatch(name);
    return chinese == null ? null : parseChineseNumber(chinese.group(1)!);
  }

  bool isDocumentName(String name) {
    final extension = p.extension(name).toLowerCase();
    return extension == '.txt' || extension == '.md';
  }

  int nextOrder(List<ContentNode> siblings) {
    return siblings.fold<int>(
          0,
          (value, node) => node.order > value ? node.order : value,
        ) +
        LibraryPaths.orderStep;
  }

  int maximumNumber(Iterable<ContentNode> nodes) {
    return nodes.fold<int>(
      0,
      (value, node) => (node.number ?? 0) > value ? node.number! : value,
    );
  }

  String contentSignature(List<ContentNode> nodes) {
    final sorted = [...nodes]
      ..sort((left, right) => left.id.value.compareTo(right.id.value));
    return sorted
        .map(
          (node) =>
              '${node.id}:${node.parentId}:${node.relativePath}:${node.order}:${node.number}:${node.role.name}',
        )
        .join('|');
  }

  int naturalCompare(String left, String right) {
    final pattern = RegExp(r'(\d+)|(\D+)');
    final leftParts = pattern.allMatches(left.toLowerCase()).toList();
    final rightParts = pattern.allMatches(right.toLowerCase()).toList();
    for (
      var index = 0;
      index < leftParts.length && index < rightParts.length;
      index += 1
    ) {
      final leftPart = leftParts[index].group(0)!;
      final rightPart = rightParts[index].group(0)!;
      final leftNumber = int.tryParse(leftPart);
      final rightNumber = int.tryParse(rightPart);
      final comparison = leftNumber != null && rightNumber != null
          ? leftNumber.compareTo(rightNumber)
          : leftPart.compareTo(rightPart);
      if (comparison != 0) {
        return comparison;
      }
    }
    return leftParts.length.compareTo(rightParts.length);
  }

  String chineseNumber(int value) {
    if (value <= 0 || value > 9999) {
      return value.toString();
    }
    const digits = ['零', '一', '二', '三', '四', '五', '六', '七', '八', '九'];
    const units = ['', '十', '百', '千'];
    final text = value.toString();
    final buffer = StringBuffer();
    var pendingZero = false;
    for (var index = 0; index < text.length; index += 1) {
      final digit = int.parse(text[index]);
      final unit = text.length - index - 1;
      if (digit == 0) {
        pendingZero = buffer.isNotEmpty;
        continue;
      }
      if (pendingZero) {
        buffer.write('零');
        pendingZero = false;
      }
      if (!(digit == 1 && unit == 1 && buffer.isEmpty)) {
        buffer.write(digits[digit]);
      }
      buffer.write(units[unit]);
    }
    return buffer.toString();
  }

  int? parseChineseNumber(String value) {
    const digits = {
      '零': 0,
      '一': 1,
      '二': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    const units = {'十': 10, '百': 100, '千': 1000};
    var total = 0;
    var current = 0;
    for (final character in value.split('')) {
      if (digits[character] case final digit?) {
        current = digit;
      } else if (units[character] case final unit?) {
        total += (current == 0 ? 1 : current) * unit;
        current = 0;
      } else {
        return null;
      }
    }
    return total + current;
  }

  LibraryFailure fileSystemFailure(FileSystemException error) {
    final errorCode = error.osError?.errorCode;
    final permissionDenied = errorCode == 1 || errorCode == 13;
    final notFound = errorCode == 2;
    final alreadyExists = errorCode == 17;
    return LibraryFailure(
      code: permissionDenied
          ? LibraryFailureCode.notWritable
          : notFound
          ? LibraryFailureCode.notFound
          : alreadyExists
          ? LibraryFailureCode.alreadyExists
          : LibraryFailureCode.io,
      message: permissionDenied
          ? '没有权限写入书库目录。'
          : notFound
          ? '文件或目录不存在。'
          : alreadyExists
          ? '目标名称已存在。'
          : '书库文件操作失败。',
    );
  }
}
