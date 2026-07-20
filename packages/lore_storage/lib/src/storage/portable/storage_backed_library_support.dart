part of '../storage_backed_library_repository.dart';

mixin _StorageBackedLibrarySupport {
  LibraryStorageFactory get storageFactory;
  IdGenerator get idGenerator;
  Clock get clock;

  Future<void> _beginMutation(
    LibraryStorageSession storage, {
    required String operation,
    required NovelId novelId,
    required String novelPath,
    required LogicalPath source,
    required LogicalPath target,
  }) async {
    if (await storage.stat(_pendingOperation) != null) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.externalModification,
          message: '存在尚未恢复的结构操作，请重新打开书库。',
        ),
      );
    }
    await _ensurePortableDirectory(storage, _pendingOperation.parent!);
    await _writeNewJson(storage, _pendingOperation, {
      'schemaVersion': 2,
      'novelId': novelId.value,
      'novelPath': novelPath,
      'operation': operation,
      'sourcePath': source.value,
      'targetPath': target.value,
      'startedAt': clock.nowUtc().toIso8601String(),
    });
  }

  Future<void> _clearPendingMutation(LibraryStorageSession storage) async {
    if (await storage.stat(_pendingOperation) != null) {
      await storage.delete(_pendingOperation, recursive: false);
    }
  }

  Future<void> _recoverPendingMutation(LibraryStorageSession storage) async {
    if (await storage.stat(_pendingOperation) == null) {
      return;
    }
    final pending = await _readJson(storage, _pendingOperation);
    final novelIdValue = pending['novelId'];
    final novelPath = pending['novelPath'];
    final operation = pending['operation'];
    final sourceValue = pending['sourcePath'];
    final targetValue = pending['targetPath'];
    if (operation == 'trashNode' ||
        operation == 'trashNovel' ||
        operation == 'trashEntry' ||
        operation == 'restoreItem') {
      await _clearPendingMutation(storage);
      return;
    }
    if (novelIdValue is! String ||
        novelPath is! String ||
        operation is! String ||
        sourceValue is! String ||
        targetValue is! String) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.metadataCorrupt,
          message: '结构操作恢复记录已损坏。',
        ),
      );
    }
    final novelId = NovelId(novelIdValue);
    final source = LogicalPath.parse(sourceValue);
    final target = LogicalPath.parse(targetValue);
    if (operation == 'renameNovel') {
      final targetExists = await storage.stat(target) != null;
      final sourceExists = await storage.stat(source) != null;
      if (targetExists && !sourceExists) {
        final snapshot = await _loadNovel(
          storage,
          NovelRegistration(id: novelId, relativePath: target.value),
        );
        if (snapshot.metadata.title != target.name) {
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
        }
        await _replaceRegistration(storage, novelId, target.value);
      }
      await _clearPendingMutation(storage);
      return;
    }
    final registration = await _registration(storage, novelId);
    final snapshot = await _loadNovel(storage, registration);
    if (operation == 'renameBody' &&
        await storage.stat(target) != null &&
        await storage.stat(source) == null) {
      final oldBody = source.value.substring(novelPath.length + 1);
      final newBody = target.value.substring(novelPath.length + 1);
      final metadata = _copyNovel(
        snapshot.metadata,
        revision: snapshot.metadata.revision + 1,
        body: NovelBody(id: snapshot.metadata.body.id, relativePath: newBody),
        updatedAt: clock.nowUtc(),
      );
      final nodes = snapshot.contentTree.nodes
          .map(
            (node) => node.copyWith(
              relativePath:
                  '$newBody/${node.relativePath.substring(oldBody.length + 1)}',
            ),
          )
          .toList(growable: false);
      await _writeNovelSnapshot(
        storage,
        novelPath,
        metadata,
        ContentTree(
          schemaVersion: 2,
          novelId: novelId,
          revision: snapshot.contentTree.revision + 1,
          nodes: nodes,
        ),
      );
    } else if (operation == 'renameNode' || operation == 'moveChapter') {
      final sourceExists = await storage.stat(source) != null;
      final targetExists = await storage.stat(target) != null;
      if (sourceExists && !targetExists) {
        await _clearPendingMutation(storage);
        return;
      }
      if (!targetExists) {
        await _clearPendingMutation(storage);
        return;
      }
      final scanned = await _scanTree(
        storage,
        LogicalPath.parse(novelPath),
        snapshot.metadata,
        snapshot.contentTree.nodes,
        revision: snapshot.contentTree.revision + 1,
      );
      await _replaceJson(
        storage,
        LogicalPath.parse('$novelPath/.lore/content.json'),
        _contentToJson(scanned),
      );
    }
    await _clearPendingMutation(storage);
  }

  Future<void> _ensurePortableDirectory(
    LibraryStorageSession storage,
    LogicalPath directory,
  ) async {
    if (directory.isRoot || await storage.stat(directory) != null) {
      return;
    }
    await _ensurePortableDirectory(storage, directory.parent!);
    await storage.createDirectory(directory);
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
    final matchedIds = <ContentId>{};
    final nodes = <ContentNode>[];
    final body = novelRoot.child(metadata.body.relativePath);
    final bodyEntries = await storage.list(body)
      ..sort((left, right) => left.path.name.compareTo(right.path.name));
    final volumeEntries = bodyEntries
        .where((entry) => entry.type == StorageEntryType.directory)
        .toList(growable: false);
    final rootChapterEntries = bodyEntries
        .where(
          (entry) =>
              entry.type == StorageEntryType.file &&
              _documentFormat(entry.path.name) != null,
        )
        .toList(growable: false);

    final detectedVolumePaths = volumeEntries
        .map((entry) => entry.path.value.substring(novelRoot.value.length + 1))
        .toSet();
    final unmatchedVolumes = volumeEntries
        .where((entry) {
          final relative = entry.path.value.substring(
            novelRoot.value.length + 1,
          );
          return existingByPath[relative]?.type != ContentNodeType.volume;
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

    var rootOrder = _nextOrder(
      existing
          .where((node) => node.parentId == metadata.body.id)
          .toList(growable: false),
    );

    Future<void> scanChapters(
      LogicalPath directory,
      ContentId parentId, {
      required String previousParentPath,
    }) async {
      final entries = await storage.list(directory)
        ..sort((left, right) => left.path.name.compareTo(right.path.name));
      final chapterPaths = entries
          .where(
            (entry) =>
                entry.type == StorageEntryType.file &&
                _documentFormat(entry.path.name) != null,
          )
          .map(
            (entry) => entry.path.value.substring(novelRoot.value.length + 1),
          )
          .toList(growable: false);
      final matches = <String, ContentNode>{};
      for (final relativePath in chapterPaths) {
        var candidate = existingByPath[relativePath];
        if (candidate?.type != ContentNodeType.chapter ||
            matchedIds.contains(candidate?.id)) {
          final previousPath = LogicalPath.parse(
            previousParentPath,
          ).child(LogicalPath.parse(relativePath).name).value;
          candidate = existingByPath[previousPath];
        }
        if (candidate?.type == ContentNodeType.chapter &&
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
        matches[unmatchedPaths.single] = missingChapters.single;
        matchedIds.add(missingChapters.single.id);
      }
      var nextOrder = _nextOrder(
        existing
            .where((node) => node.parentId == parentId)
            .toList(growable: false),
      );
      for (final relativePath in chapterPaths) {
        final matched = matches[relativePath];
        if (matched != null) {
          // 已匹配节点（含 1:1 重命名检测）按当前文件名重算 number/role，
          // 否则外部重命名后元数据会与文件名错位。
          nodes.add(
            _renumberNode(matched.copyWith(parentId: parentId), relativePath),
          );
        } else {
          nodes.add(
            ContentNode(
              id: ContentId(idGenerator.generate()),
              type: ContentNodeType.chapter,
              parentId: parentId,
              relativePath: relativePath,
              order: nextOrder,
              number: _chapterNumber(relativePath),
              role: _chapterRole(relativePath),
            ),
          );
          nextOrder += 1000;
        }
      }
    }

    for (final entry in volumeEntries) {
      final relative = entry.path.value.substring(novelRoot.value.length + 1);
      final exact = existingByPath[relative];
      final matched = exact?.type == ContentNodeType.volume
          ? exact
          : renamedVolume;
      final previousPath = matched?.relativePath ?? relative;
      final volume = matched != null
          // 已匹配卷（含重命名检测）按当前目录名重算 number。
          ? _renumberNode(
              matched.copyWith(parentId: metadata.body.id),
              relative,
            )
          : ContentNode(
              id: ContentId(idGenerator.generate()),
              type: ContentNodeType.volume,
              parentId: metadata.body.id,
              relativePath: relative,
              order: rootOrder,
              // 与章节一致：从「第N卷」文件名解析编号；非编号卷名（如「外传」）为 null。
              number: _volumeNumber(relative),
              role: ContentRole.normal,
            );
      if (matched == null) {
        rootOrder += 1000;
      }
      matchedIds.add(volume.id);
      nodes.add(volume);
      await scanChapters(
        entry.path,
        volume.id,
        previousParentPath: previousPath,
      );
    }

    if (rootChapterEntries.isNotEmpty) {
      await scanChapters(
        body,
        metadata.body.id,
        previousParentPath: metadata.body.relativePath,
      );
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
    NovelMetadata metadata;
    ContentTree tree;
    try {
      metadata = _novelFromJson(
        await _readJson(storage, metadataRoot.child('novel.json')),
      );
      tree = _contentFromJson(
        await _readJson(storage, metadataRoot.child('content.json')),
      );
      _validateNovelPaths(registration, metadata, tree);
    } on FormatException {
      throw _metadataCorrupt();
    } on TypeError {
      throw _metadataCorrupt();
    } on ArgumentError {
      throw _metadataCorrupt();
    }
    if (metadata.id != registration.id || tree.novelId != metadata.id) {
      throw _metadataCorrupt();
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
    final body = value['body'];
    final cover = value['cover'];
    if (value['schemaVersion'] != 2 ||
        value['revision'] is! int ||
        value['novelId'] is! String ||
        value['title'] is! String ||
        value['description'] is! String ||
        (cover != null && cover is! String) ||
        body is! Map<String, Object?> ||
        body['id'] is! String ||
        body['path'] is! String ||
        value['createdAt'] is! String ||
        value['updatedAt'] is! String) {
      throw const FormatException('Invalid novel metadata.');
    }
    final chapterFormat = switch (value['chapterFormat']) {
      'text' => ChapterFormat.text,
      'markdown' => ChapterFormat.markdown,
      _ => throw const FormatException('Invalid chapter format.'),
    };
    final numberingMode = switch (value['numberingMode']) {
      'continuous' => NumberingMode.continuous,
      'perVolume' => NumberingMode.perVolume,
      _ => throw const FormatException('Invalid numbering mode.'),
    };
    return NovelMetadata(
      schemaVersion: 2,
      revision: value['revision']! as int,
      id: NovelId(value['novelId']! as String),
      title: value['title']! as String,
      description: value['description']! as String,
      coverPath: cover as String?,
      body: NovelBody(
        id: ContentId(body['id']! as String),
        relativePath: body['path']! as String,
      ),
      chapterFormat: chapterFormat,
      numberingMode: numberingMode,
      createdAt: DateTime.parse(value['createdAt']! as String).toUtc(),
      updatedAt: DateTime.parse(value['updatedAt']! as String).toUtc(),
    );
  }

  void _validateNovelPaths(
    NovelRegistration registration,
    NovelMetadata metadata,
    ContentTree tree,
  ) {
    final root = LogicalPath.parse(registration.relativePath);
    if (root.parent != LogicalPath.root || _isHiddenPath(root)) {
      throw const FormatException('Invalid novel root path.');
    }
    final body = LogicalPath.parse(metadata.body.relativePath);
    if (body.isRoot || _isHiddenPath(body)) {
      throw const FormatException('Invalid novel body path.');
    }
    final coverPath = metadata.coverPath;
    if (coverPath != null) {
      final cover = LogicalPath.parse(coverPath);
      if (cover.isRoot || _isHiddenPath(cover)) {
        throw const FormatException('Invalid novel cover path.');
      }
    }
    for (final node in tree.nodes) {
      final path = LogicalPath.parse(node.relativePath);
      if (!body.contains(path) || _isHiddenPath(path)) {
        throw const FormatException('Invalid content node path.');
      }
    }
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

  ContentTree _contentFromJson(Map<String, Object?> value) {
    if (value['schemaVersion'] != 2 ||
        value['novelId'] is! String ||
        value['revision'] is! int ||
        value['nodes'] is! List<Object?>) {
      throw const FormatException('Invalid content metadata.');
    }
    return ContentTree(
      schemaVersion: 2,
      novelId: NovelId(value['novelId']! as String),
      revision: value['revision']! as int,
      nodes: (value['nodes']! as List<Object?>)
          .map(_contentNodeFromJson)
          .toList(),
    );
  }

  ContentNode _contentNodeFromJson(Object? raw) {
    if (raw is! Map<String, Object?> ||
        raw['id'] is! String ||
        raw['parentId'] is! String ||
        raw['path'] is! String ||
        raw['order'] is! int ||
        (raw['number'] != null && raw['number'] is! int) ||
        (raw['characterCount'] != null && raw['characterCount'] is! int)) {
      throw const FormatException('Invalid content node.');
    }
    final type = switch (raw['type']) {
      'volume' => ContentNodeType.volume,
      'chapter' => ContentNodeType.chapter,
      _ => throw const FormatException('Invalid content node type.'),
    };
    final role = switch (raw['role']) {
      'normal' => ContentRole.normal,
      'prologue' => ContentRole.prologue,
      'epilogue' => ContentRole.epilogue,
      'extra' => ContentRole.extra,
      _ => throw const FormatException('Invalid content node role.'),
    };
    return ContentNode(
      id: ContentId(raw['id']! as String),
      type: type,
      parentId: ContentId(raw['parentId']! as String),
      relativePath: raw['path']! as String,
      order: raw['order']! as int,
      number: raw['number'] as int?,
      role: role,
      characterCount: raw['characterCount'] as int?,
    );
  }

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
            'characterCount': node.characterCount,
            'role': node.role.name,
          },
        )
        .toList(),
  };

  List<NovelRegistration> _registrations(Map<String, Object?> library) {
    final novels = library['novels'];
    if (novels is! List<Object?>) {
      throw const FormatException('Invalid novel registrations.');
    }
    return novels.map((raw) {
      if (raw is! Map<String, Object?> ||
          raw['id'] is! String ||
          raw['path'] is! String) {
        throw const FormatException('Invalid novel registration.');
      }
      final path = LogicalPath.parse(raw['path']! as String);
      if (path.isRoot || _isHiddenPath(path)) {
        throw const FormatException('Invalid novel registration path.');
      }
      return NovelRegistration(
        id: NovelId(raw['id']! as String),
        relativePath: path.value,
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

  void _validateDocumentRef(DocumentRef ref) {
    final actual = _documentFormat(_publicPath(ref.relativePath).name);
    if (actual != ref.format) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.unsupportedFormat,
          message: '文件格式与文档类型不匹配。',
        ),
      );
    }
  }

  bool _isHiddenPath(LogicalPath path) =>
      path.value.split('/').any((segment) => segment.startsWith('.'));

  LogicalPath _publicPath(String value) {
    try {
      final path = LogicalPath.parse(value.replaceAll(r'\', '/'));
      if (_isHiddenPath(path)) {
        throw _invalid('不能直接访问内部或隐藏路径。');
      }
      return path;
    } on FormatException {
      throw _invalid('书库路径无效。');
    }
  }

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
      throw _invalidName('名称无效。');
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

  int? _chapterNumber(String relativePath) {
    final name = LogicalPath.parse(relativePath).name;
    final stem = name.substring(0, name.length - _extension(name).length);
    final match = RegExp(r'^第(\d+)章').firstMatch(stem);
    return match == null ? null : int.parse(match.group(1)!);
  }

  int? _volumeNumber(String relativePath) {
    final name = LogicalPath.parse(relativePath).name;
    final stem = name.substring(0, name.length - _extension(name).length);
    final match = RegExp(r'^第(\d+)卷').firstMatch(stem);
    return match == null ? null : int.parse(match.group(1)!);
  }

  ContentRole _chapterRole(String relativePath) {
    final name = LogicalPath.parse(relativePath).name;
    final stem = name.substring(0, name.length - _extension(name).length);
    if (stem.startsWith('序章')) return ContentRole.prologue;
    if (stem.startsWith('后记')) return ContentRole.epilogue;
    if (stem.startsWith('番外')) return ContentRole.extra;
    return ContentRole.normal;
  }

  /// 按 [relativePath] 的文件名重算节点派生字段（number、role）并更新路径。
  ///
  /// 章节用 `_chapterNumber`、卷用 `_volumeNumber`。重命名为无编号名字（如
  /// 「第3章」→「楔子」）时 number 解析为 null 并清空——该编号不再被
  /// `_maxNumber` 计入；若它恰为最大编号，下次新建即复用，否则不会回填
  /// 空洞，仅保持元数据与文件名一致。章节 role 按前缀（序章/后记/番外）
  /// 重算，卷恒为 normal。供 `renameNode` 与扫描器的「已匹配/重命名检测」
  /// 分支共用，确保两条路径行为一致。
  ContentNode _renumberNode(ContentNode node, String relativePath) {
    final isChapter = node.type == ContentNodeType.chapter;
    final parsed = isChapter
        ? _chapterNumber(relativePath)
        : _volumeNumber(relativePath);
    return node.copyWith(
      relativePath: relativePath,
      number: parsed,
      clearNumber: parsed == null,
      role: isChapter ? _chapterRole(relativePath) : node.role,
    );
  }

  LibraryOperationException _invalid(String message) =>
      LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.invalidLocation,
          message: message,
        ),
      );

  LibraryOperationException _invalidName(String message) =>
      LibraryOperationException(
        LibraryFailure(code: LibraryFailureCode.invalidName, message: message),
      );

  LibraryOperationException _metadataCorrupt() =>
      const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.metadataCorrupt,
          message: '小说元数据无效。',
        ),
      );

  LibraryOperationException _notFound() => const LibraryOperationException(
    LibraryFailure(code: LibraryFailureCode.notFound, message: '文件或目录不存在。'),
  );
}
