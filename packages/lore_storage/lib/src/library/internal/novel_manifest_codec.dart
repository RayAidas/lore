import 'dart:io';

import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:path/path.dart' as p;

import 'library_path_resolver.dart';
import 'library_paths.dart';
import 'library_storage_io.dart';

/// 小说 / 内容树 / 书库 manifest 的编解码与读写。
///
/// 所有方法按原 [LocalDirectoryLibraryRepository] 中的实现逐字搬迁。
final class NovelManifestCodec {
  NovelManifestCodec({
    required this.paths,
    required this.io,
    required this.clock,
    required this.resolver,
  });

  final LibraryPaths paths;
  final LibraryStorageIo io;
  final Clock clock;
  final LibraryPathResolver resolver;

  List<NovelRegistration> parseNovelRegistrations(Object? value) {
    if (value is! List<Object?>) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.metadataCorrupt,
          message: '书库小说注册信息无效。',
        ),
      );
    }
    return value.map((item) {
      if (item is! Map<String, Object?> ||
          item['id'] is! String ||
          item['path'] is! String ||
          !io.isUuid(item['id']! as String)) {
        throw const LibraryOperationException(
          LibraryFailure(
            code: LibraryFailureCode.metadataCorrupt,
            message: '书库包含无效的小说注册项。',
          ),
        );
      }
      return NovelRegistration(
        id: NovelId(item['id']! as String),
        relativePath: item['path']! as String,
      );
    }).toList();
  }

  NovelMetadata parseNovelMetadata(Map<String, Object?> value) {
    final body = value['body'];
    final novelId = value['novelId'];
    final createdAt = value['createdAt'];
    final updatedAt = value['updatedAt'];
    if (value['schemaVersion'] != LibraryPaths.schemaVersion ||
        novelId is! String ||
        !io.isUuid(novelId) ||
        value['title'] is! String ||
        value['description'] is! String ||
        body is! Map<String, Object?> ||
        body['id'] is! String ||
        !io.isUuid(body['id']! as String) ||
        body['path'] is! String ||
        !paths.isMetadataRelativePath(body['path']! as String) ||
        createdAt is! String ||
        updatedAt is! String) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.metadataCorrupt,
          message: '小说元数据无效。',
        ),
      );
    }
    final chapterFormat = switch (value['chapterFormat']) {
      'text' => ChapterFormat.text,
      'markdown' => ChapterFormat.markdown,
      _ => null,
    };
    final numberingMode = switch (value['numberingMode']) {
      'continuous' => NumberingMode.continuous,
      'perVolume' => NumberingMode.perVolume,
      _ => null,
    };
    final created = DateTime.tryParse(createdAt);
    final updated = DateTime.tryParse(updatedAt);
    if (chapterFormat == null ||
        numberingMode == null ||
        created == null ||
        updated == null) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.metadataCorrupt,
          message: '小说设置或时间信息无效。',
        ),
      );
    }
    return NovelMetadata(
      schemaVersion: LibraryPaths.schemaVersion,
      id: NovelId(novelId),
      title: value['title']! as String,
      description: value['description']! as String,
      coverPath: value['cover'] as String?,
      body: NovelBody(
        id: ContentId(body['id']! as String),
        relativePath: body['path']! as String,
      ),
      chapterFormat: chapterFormat,
      numberingMode: numberingMode,
      createdAt: created.toUtc(),
      updatedAt: updated.toUtc(),
    );
  }

  ContentTree parseContentTree(Map<String, Object?> value) {
    final novelId = value['novelId'];
    final nodes = value['nodes'];
    if (value['schemaVersion'] != LibraryPaths.schemaVersion ||
        novelId is! String ||
        !io.isUuid(novelId) ||
        value['revision'] is! int ||
        nodes is! List<Object?>) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.metadataCorrupt,
          message: '正文内容树无效。',
        ),
      );
    }
    return ContentTree(
      schemaVersion: LibraryPaths.schemaVersion,
      novelId: NovelId(novelId),
      revision: value['revision']! as int,
      nodes: nodes.map(parseContentNode).toList(growable: false),
    );
  }

  ContentNode parseContentNode(Object? value) {
    if (value is! Map<String, Object?> ||
        value['id'] is! String ||
        !io.isUuid(value['id']! as String) ||
        value['parentId'] is! String ||
        !io.isUuid(value['parentId']! as String) ||
        value['path'] is! String ||
        !paths.isMetadataRelativePath(value['path']! as String) ||
        value['order'] is! int ||
        (value['number'] != null && value['number'] is! int)) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.metadataCorrupt,
          message: '正文内容节点无效。',
        ),
      );
    }
    final type = switch (value['type']) {
      'volume' => ContentNodeType.volume,
      'chapter' => ContentNodeType.chapter,
      _ => null,
    };
    final role = switch (value['role']) {
      'normal' => ContentRole.normal,
      'prologue' => ContentRole.prologue,
      'epilogue' => ContentRole.epilogue,
      'extra' => ContentRole.extra,
      _ => null,
    };
    if (type == null || role == null) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.metadataCorrupt,
          message: '正文内容节点类型无效。',
        ),
      );
    }
    return ContentNode(
      id: ContentId(value['id']! as String),
      type: type,
      parentId: ContentId(value['parentId']! as String),
      relativePath: value['path']! as String,
      order: value['order']! as int,
      number: value['number'] as int?,
      role: role,
    );
  }

  Map<String, Object?> novelToJson(NovelMetadata metadata) => {
    'schemaVersion': metadata.schemaVersion,
    'novelId': metadata.id.value,
    'title': metadata.title,
    'description': metadata.description,
    'cover': metadata.coverPath,
    'body': {'id': metadata.body.id.value, 'path': metadata.body.relativePath},
    'chapterFormat': metadata.chapterFormat.name,
    'numberingMode': metadata.numberingMode.name,
    'createdAt': metadata.createdAt.toUtc().toIso8601String(),
    'updatedAt': metadata.updatedAt.toUtc().toIso8601String(),
  };

  Map<String, Object?> contentToJson(ContentTree tree) => {
    'schemaVersion': tree.schemaVersion,
    'novelId': tree.novelId.value,
    'revision': tree.revision,
    'nodes': tree.nodes
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
        .toList(growable: false),
  };

  Map<String, Object?> toJson(LibraryMetadata metadata) {
    return {
      'schemaVersion': metadata.schemaVersion,
      'libraryId': metadata.id.value,
      'createdAt': metadata.createdAt.toUtc().toIso8601String(),
      'updatedAt': metadata.updatedAt.toUtc().toIso8601String(),
      'novels': metadata.novels
          .map((novel) => {'id': novel.id.value, 'path': novel.relativePath})
          .toList(growable: false),
      'templates': <Object?>[],
    };
  }

  Future<NovelRegistration> registrationFor(
    String rootPath,
    NovelId novelId,
  ) async {
    final manifest = await io.readJsonObject(
      File(paths.manifestPath(rootPath)),
    );
    for (final registration in parseNovelRegistrations(manifest['novels'])) {
      if (registration.id == novelId) {
        return registration;
      }
    }
    throw const LibraryOperationException(
      LibraryFailure(code: LibraryFailureCode.notFound, message: '小说未在书库中注册。'),
    );
  }

  Future<void> registerNovel(
    String rootPath,
    NovelId novelId,
    String relativePath,
  ) async {
    final file = File(paths.manifestPath(rootPath));
    final manifest = await io.readJsonObject(file);
    final registrations = parseNovelRegistrations(manifest['novels']);
    final idConflict = registrations.where(
      (item) => item.id == novelId && item.relativePath != relativePath,
    );
    final pathConflict = registrations.where(
      (item) => item.relativePath == relativePath && item.id != novelId,
    );
    if (idConflict.isNotEmpty || pathConflict.isNotEmpty) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.metadataCorrupt,
          message: '小说 ID 或注册路径与现有记录冲突。',
        ),
      );
    }
    if (!registrations.any((item) => item.id == novelId)) {
      registrations.add(
        NovelRegistration(id: novelId, relativePath: relativePath),
      );
    }
    manifest['novels'] = registrations
        .map((item) => {'id': item.id.value, 'path': item.relativePath})
        .toList(growable: false);
    manifest['updatedAt'] = clock.nowUtc().toIso8601String();
    await io.writeJsonAtomic(file, manifest);
  }

  Future<void> updateNovelRegistration(
    String rootPath,
    NovelId novelId,
    String relativePath,
  ) async {
    final file = File(paths.manifestPath(rootPath));
    final manifest = await io.readJsonObject(file);
    final registrations = parseNovelRegistrations(manifest['novels']);
    final index = registrations.indexWhere((item) => item.id == novelId);
    if (index < 0) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.notFound,
          message: '小说未在书库中注册。',
        ),
      );
    }
    if (registrations.any(
      (item) => item.id != novelId && item.relativePath == relativePath,
    )) {
      throw io.alreadyExists(relativePath);
    }
    registrations[index] = NovelRegistration(
      id: novelId,
      relativePath: relativePath,
    );
    manifest['novels'] = registrations
        .map((item) => {'id': item.id.value, 'path': item.relativePath})
        .toList(growable: false);
    manifest['updatedAt'] = clock.nowUtc().toIso8601String();
    await io.writeJsonAtomic(file, manifest);
  }

  Future<void> removeNovelRegistration(String rootPath, NovelId novelId) async {
    final file = File(paths.manifestPath(rootPath));
    final manifest = await io.readJsonObject(file);
    final registrations = parseNovelRegistrations(manifest['novels']);
    manifest['novels'] = registrations
        .where((registration) => registration.id != novelId)
        .map(
          (registration) => {
            'id': registration.id.value,
            'path': registration.relativePath,
          },
        )
        .toList();
    manifest['updatedAt'] = clock.nowUtc().toIso8601String();
    await io.writeJsonAtomic(file, manifest);
  }

  Future<NovelMetadata> loadNovelMetadata(
    String rootPath,
    NovelRegistration registration,
  ) async {
    final novelRoot = await resolver.resolveExistingDirectory(
      rootPath,
      registration.relativePath,
    );
    final metadata = parseNovelMetadata(
      await io.readJsonObject(File(paths.novelManifestPath(novelRoot))),
    );
    if (metadata.id != registration.id) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.metadataCorrupt,
          message: '书库注册信息与小说元数据不一致。',
        ),
      );
    }
    return metadata;
  }

  Future<NovelSnapshot> loadNovel(
    String rootPath,
    NovelRegistration registration,
  ) async {
    final metadata = await loadNovelMetadata(rootPath, registration);
    final novelRoot = p.join(rootPath, registration.relativePath);
    final tree = parseContentTree(
      await io.readJsonObject(File(paths.contentManifestPath(novelRoot))),
    );
    if (tree.novelId != metadata.id) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.metadataCorrupt,
          message: '小说与内容树的 ID 不一致。',
        ),
      );
    }
    return NovelSnapshot(
      rootPath: registration.relativePath,
      metadata: metadata,
      contentTree: tree,
    );
  }

  /// 列出书库根级目录时为条目附加小说/正文/卷/章节语义信息。
  Future<List<LibraryEntry>> annotateEntries(
    String rootPath,
    String relativePath,
    List<LibraryEntry> entries,
    Future<NovelSnapshot> Function(
      String rootPath,
      NovelRegistration registration,
    )
    loadNovelFn,
  ) async {
    final manifestFile = File(paths.manifestPath(rootPath));
    if (!await manifestFile.exists()) {
      return entries;
    }
    final manifest = await io.readJsonObject(manifestFile);
    final registrations = parseNovelRegistrations(manifest['novels']);
    if (relativePath.isEmpty) {
      final novelIdsByPath = <String, NovelId>{};
      for (final registration in registrations) {
        if (!entries.any(
          (entry) => entry.relativePath == registration.relativePath,
        )) {
          continue;
        }
        try {
          final metadata = await loadNovelMetadata(rootPath, registration);
          novelIdsByPath[registration.relativePath] = metadata.id;
        } on LibraryOperationException {
          continue;
        }
      }
      return entries
          .map((entry) {
            final novelId = novelIdsByPath[entry.relativePath];
            if (novelId == null) {
              return entry;
            }
            return semanticEntry(
              name: entry.name,
              relativePath: entry.relativePath,
              type: entry.type,
              kind: LibraryEntrySemanticKind.novel,
              semanticId: novelId.value,
              novelId: novelId.value,
            );
          })
          .toList(growable: false);
    }

    final registration = registrations
        .where(
          (item) =>
              relativePath == item.relativePath ||
              p.isWithin(item.relativePath, relativePath),
        )
        .firstOrNull;
    if (registration == null) {
      return entries;
    }
    NovelSnapshot snapshot;
    try {
      snapshot = await loadNovelFn(rootPath, registration);
    } on LibraryOperationException {
      return entries;
    }
    return entries
        .map((entry) {
          if (!p.isWithin(snapshot.rootPath, entry.relativePath)) {
            return entry;
          }
          final novelRelative = p.relative(
            entry.relativePath,
            from: snapshot.rootPath,
          );
          if (novelRelative == snapshot.metadata.body.relativePath) {
            return semanticEntry(
              name: entry.name,
              relativePath: entry.relativePath,
              type: entry.type,
              kind: LibraryEntrySemanticKind.body,
              semanticId: snapshot.metadata.body.id.value,
              novelId: snapshot.metadata.id.value,
            );
          }
          final node = snapshot.contentTree.nodes
              .where((candidate) => candidate.relativePath == novelRelative)
              .firstOrNull;
          if (node == null) {
            return entry;
          }
          return semanticEntry(
            name: entry.name,
            relativePath: entry.relativePath,
            type: entry.type,
            kind: node.type == ContentNodeType.volume
                ? LibraryEntrySemanticKind.volume
                : LibraryEntrySemanticKind.chapter,
            semanticId: node.id.value,
            novelId: snapshot.metadata.id.value,
            semanticOrder: node.order,
          );
        })
        .toList(growable: false);
  }

  LibraryEntry semanticEntry({
    required String name,
    required String relativePath,
    required LibraryEntryType type,
    required LibraryEntrySemanticKind kind,
    required String semanticId,
    required String novelId,
    int? semanticOrder,
  }) {
    return LibraryEntry(
      name: name,
      relativePath: relativePath,
      type: type,
      semanticKind: kind,
      semanticId: semanticId,
      novelId: novelId,
      semanticOrder: semanticOrder,
    );
  }
}
