import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:path/path.dart' as p;

final class LocalDirectoryLibraryRepository
    implements
        LibraryRepository,
        LibraryTreeRepository,
        DocumentRepository,
        NovelRepository,
        ContentTreeRepository,
        TrashRepository {
  const LocalDirectoryLibraryRepository({
    required this._idGenerator,
    required this._clock,
    this.fileOperationsGateway,
  });

  static const _schemaVersion = 1;
  static const _metadataDirectoryName = '.lore';
  static const _manifestFileName = 'library.json';
  static const _novelManifestFileName = 'novel.json';
  static const _contentManifestFileName = 'content.json';
  static const _bodyDirectoryName = '正文';
  static const _orderStep = 1000;
  static const _recoveryDirectoryName = 'recovery';
  static const _trashDirectoryName = 'trash';
  static const _pendingOperationFileName = 'pending-operation.json';
  static const _trashManifestFileName = 'index.json';

  final IdGenerator _idGenerator;
  final Clock _clock;
  final LibraryFileOperationsGateway? fileOperationsGateway;

  @override
  Future<LibraryInspection> inspect(LibraryAccess access) async {
    try {
      final rootPath = await _resolveRoot(access);
      final metadataDirectoryPath = p.join(rootPath, _metadataDirectoryName);
      final metadataType = await FileSystemEntity.type(
        metadataDirectoryPath,
        followLinks: false,
      );
      if (metadataType == FileSystemEntityType.notFound) {
        return const LibraryInspectionNeedsInitialization();
      }
      if (metadataType != FileSystemEntityType.directory) {
        return const LibraryInspectionFailure(
          LibraryFailure(
            code: LibraryFailureCode.invalidLocation,
            message: '.lore 已存在，但不是普通文件夹。',
          ),
        );
      }

      final manifest = File(_manifestPath(rootPath));
      final manifestType = await FileSystemEntity.type(
        manifest.path,
        followLinks: false,
      );
      if (manifestType == FileSystemEntityType.notFound) {
        return const LibraryInspectionNeedsInitialization();
      }
      if (manifestType != FileSystemEntityType.file) {
        return const LibraryInspectionFailure(
          LibraryFailure(
            code: LibraryFailureCode.invalidLocation,
            message: '书库元数据必须是普通文件。',
          ),
        );
      }

      var value = jsonDecode(await manifest.readAsString());
      if (value is! Map<String, Object?>) {
        return _corrupt('书库元数据不是有效的 JSON 对象。');
      }

      final schemaVersion = value['schemaVersion'];
      if (schemaVersion is! int) {
        return _corrupt('书库元数据缺少 schemaVersion。');
      }
      if (schemaVersion != _schemaVersion) {
        return LibraryInspectionFailure(
          LibraryFailure(
            code: LibraryFailureCode.unsupportedSchema,
            message: '当前版本不支持书库格式版本 $schemaVersion。',
          ),
        );
      }

      final libraryId = value['libraryId'];
      final createdAt = value['createdAt'];
      final updatedAt = value['updatedAt'];
      if (libraryId is! String || !_isUuid(libraryId)) {
        return _corrupt('书库 ID 无效。');
      }
      if (createdAt is! String || updatedAt is! String) {
        return _corrupt('书库时间信息无效。');
      }
      if (value['novels'] is! List<Object?> ||
          value['templates'] is! List<Object?>) {
        return _corrupt('书库注册信息无效。');
      }

      final created = DateTime.tryParse(createdAt);
      final updated = DateTime.tryParse(updatedAt);
      if (created == null || updated == null) {
        return _corrupt('书库时间信息无法解析。');
      }

      await _recoverPending(rootPath);
      value = jsonDecode(await manifest.readAsString());
      if (value is! Map<String, Object?>) {
        return _corrupt('恢复后的书库元数据无效。');
      }

      final novels = _parseNovelRegistrations(value['novels']);
      return LibraryInspectionReady(
        LibraryMetadata(
          schemaVersion: schemaVersion,
          id: LibraryId(libraryId),
          createdAt: created.toUtc(),
          updatedAt: updated.toUtc(),
          novels: novels,
        ),
      );
    } on FormatException {
      return _corrupt('书库元数据 JSON 已损坏。');
    } on FileSystemException catch (error) {
      return LibraryInspectionFailure(_fileSystemFailure(error));
    } on LibraryOperationException catch (error) {
      return LibraryInspectionFailure(error.failure);
    }
  }

  @override
  Future<LibraryMetadata> initialize(LibraryAccess access) async {
    String? createdManifestPath;
    try {
      final rootPath = await _resolveRoot(access);
      final existing = await inspect(access);
      if (existing case LibraryInspectionReady(:final metadata)) {
        return metadata;
      }
      if (existing case LibraryInspectionFailure(:final failure)) {
        throw LibraryOperationException(failure);
      }

      final metadataDirectory = Directory(
        p.join(rootPath, _metadataDirectoryName),
      );
      final metadataType = await FileSystemEntity.type(
        metadataDirectory.path,
        followLinks: false,
      );
      if (metadataType != FileSystemEntityType.notFound &&
          metadataType != FileSystemEntityType.directory) {
        throw const LibraryOperationException(
          LibraryFailure(
            code: LibraryFailureCode.notWritable,
            message: '.lore 已存在，但不是文件夹。',
          ),
        );
      }
      await metadataDirectory.create(recursive: true);

      final now = _clock.nowUtc();
      final metadata = LibraryMetadata(
        schemaVersion: _schemaVersion,
        id: LibraryId(_idGenerator.generate()),
        createdAt: now,
        updatedAt: now,
        novels: const [],
      );
      final manifestPath = _manifestPath(rootPath);
      final manifest = File(manifestPath);
      try {
        await manifest.create(exclusive: true);
        createdManifestPath = manifestPath;
      } on PathExistsException {
        throw const LibraryOperationException(
          LibraryFailure(
            code: LibraryFailureCode.metadataCorrupt,
            message: '初始化期间检测到已有书库元数据，未执行覆盖。',
          ),
        );
      }
      await manifest.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(_toJson(metadata))}\n',
        flush: true,
      );
      createdManifestPath = null;
      return metadata;
    } on LibraryOperationException {
      rethrow;
    } on FileSystemException catch (error) {
      throw LibraryOperationException(_fileSystemFailure(error));
    } finally {
      if (createdManifestPath != null) {
        await _deleteFileSafely(createdManifestPath);
      }
    }
  }

  @override
  Future<List<LibraryEntry>> listChildren(
    LibraryAccess access, {
    String relativePath = '',
  }) async {
    try {
      final rootPath = await _resolveRoot(access);
      if (relativePath.isNotEmpty && _isHiddenPath(relativePath)) {
        throw const LibraryOperationException(
          LibraryFailure(
            code: LibraryFailureCode.invalidLocation,
            message: '不能访问书库内部目录。',
          ),
        );
      }
      final directoryPath = await _resolveChildPath(rootPath, relativePath);
      final directory = Directory(directoryPath);
      if (!await directory.exists()) {
        throw const LibraryOperationException(
          LibraryFailure(
            code: LibraryFailureCode.notFound,
            message: '目录不存在或已被移动。',
          ),
        );
      }

      final entries = <LibraryEntry>[];
      await for (final entity in directory.list(followLinks: false)) {
        final name = p.basename(entity.path);
        if (name.startsWith('.')) {
          continue;
        }
        final type = await FileSystemEntity.type(
          entity.path,
          followLinks: false,
        );
        if (type == FileSystemEntityType.link ||
            type == FileSystemEntityType.notFound) {
          continue;
        }
        entries.add(
          LibraryEntry(
            name: name,
            relativePath: p.relative(entity.path, from: rootPath),
            type: _entryType(name, type),
          ),
        );
      }
      final annotated = await _annotateEntries(rootPath, relativePath, entries);
      annotated.sort(_compareEntries);
      return annotated;
    } on LibraryOperationException {
      rethrow;
    } on FileSystemException catch (error) {
      throw LibraryOperationException(_fileSystemFailure(error));
    }
  }

  @override
  Future<LibraryEntry> createDirectory(
    LibraryAccess access, {
    required String parentPath,
    required String name,
  }) async {
    try {
      final rootPath = await _resolveRoot(access);
      final parent = await _resolveExistingDirectory(rootPath, parentPath);
      final validName = _validateName(name);
      final targetPath = p.join(parent, validName);
      if (await FileSystemEntity.type(targetPath, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw _alreadyExists(validName);
      }
      await Directory(targetPath).create();
      return _entryForPath(
        rootPath,
        targetPath,
        FileSystemEntityType.directory,
      );
    } on LibraryOperationException {
      rethrow;
    } on FileSystemException catch (error) {
      throw LibraryOperationException(_fileSystemFailure(error));
    }
  }

  @override
  Future<LibraryEntry> createDocument(
    LibraryAccess access, {
    required String parentPath,
    required String name,
    required DocumentFormat format,
    String initialText = '',
  }) async {
    String? createdPath;
    try {
      final rootPath = await _resolveRoot(access);
      final parent = await _resolveExistingDirectory(rootPath, parentPath);
      final fileName = _documentFileName(name, format);
      final targetPath = p.join(parent, fileName);
      final file = File(targetPath);
      try {
        await file.create(exclusive: true);
        createdPath = targetPath;
      } on PathExistsException {
        throw _alreadyExists(fileName);
      }
      await file.writeAsBytes(utf8.encode(initialText), flush: true);
      createdPath = null;
      return _entryForPath(rootPath, targetPath, FileSystemEntityType.file);
    } on LibraryOperationException {
      rethrow;
    } on FileSystemException catch (error) {
      throw LibraryOperationException(_fileSystemFailure(error));
    } finally {
      if (createdPath != null) {
        await _deleteFileSafely(createdPath);
      }
    }
  }

  @override
  Future<LibraryEntry> renameEntry(
    LibraryAccess access, {
    required String relativePath,
    required String newName,
  }) async {
    try {
      final rootPath = await _resolveRoot(access);
      final sourcePath = await _resolveExistingEntity(rootPath, relativePath);
      final sourceType = await FileSystemEntity.type(
        sourcePath,
        followLinks: false,
      );
      final currentName = p.basename(sourcePath);
      final validName = sourceType == FileSystemEntityType.file
          ? _renamedDocumentName(currentName, newName)
          : _validateName(newName);
      if (validName == currentName) {
        return _entryForPath(rootPath, sourcePath, sourceType);
      }

      final targetPath = p.join(p.dirname(sourcePath), validName);
      final targetType = await FileSystemEntity.type(
        targetPath,
        followLinks: false,
      );
      final caseOnlyRename =
          targetType != FileSystemEntityType.notFound &&
          p.equals(targetPath.toLowerCase(), sourcePath.toLowerCase());
      if (targetType != FileSystemEntityType.notFound && !caseOnlyRename) {
        throw _alreadyExists(validName);
      }

      final renamedPath = caseOnlyRename
          ? await _renameChangingCase(
              access,
              rootPath,
              sourcePath,
              targetPath,
              sourceType,
            )
          : await _renameEntity(
              access,
              rootPath,
              sourcePath,
              targetPath,
              sourceType,
            );
      return _entryForPath(rootPath, renamedPath, sourceType);
    } on LibraryOperationException {
      rethrow;
    } on FileSystemException catch (error) {
      throw LibraryOperationException(_fileSystemFailure(error));
    }
  }

  @override
  Future<List<NovelSnapshot>> listNovels(LibraryAccess access) async {
    final rootPath = await _resolveRoot(access);
    final manifest = await _readJsonObject(File(_manifestPath(rootPath)));
    final novels = <NovelSnapshot>[];
    for (final registration in _parseNovelRegistrations(manifest['novels'])) {
      try {
        novels.add(await _loadNovel(rootPath, registration));
      } on LibraryOperationException catch (error) {
        if (error.failure.code != LibraryFailureCode.notFound) {
          rethrow;
        }
      }
    }
    return novels;
  }

  @override
  Future<NovelSnapshot> loadNovel(
    LibraryAccess access, {
    required NovelId novelId,
  }) async {
    final rootPath = await _resolveRoot(access);
    return _loadNovel(rootPath, await _registrationFor(rootPath, novelId));
  }

  @override
  Future<NovelStructureMutation> createNovel(
    LibraryAccess access, {
    required String title,
    ChapterFormat chapterFormat = ChapterFormat.markdown,
  }) async {
    final rootPath = await _resolveRoot(access);
    final validTitle = _validateName(title);
    final novelRoot = p.join(rootPath, validTitle);
    if (await FileSystemEntity.type(novelRoot, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw _alreadyExists(validTitle);
    }

    final now = _clock.nowUtc();
    final metadata = NovelMetadata(
      schemaVersion: _schemaVersion,
      id: NovelId(_idGenerator.generate()),
      title: validTitle,
      description: '',
      coverPath: null,
      body: NovelBody(
        id: ContentId(_idGenerator.generate()),
        relativePath: _bodyDirectoryName,
      ),
      chapterFormat: chapterFormat,
      numberingMode: NumberingMode.continuous,
      createdAt: now,
      updatedAt: now,
    );
    final tree = ContentTree(
      schemaVersion: _schemaVersion,
      novelId: metadata.id,
      revision: 0,
      nodes: const [],
    );
    await _writePending(
      rootPath,
      metadata.id,
      validTitle,
      operation: 'createNovel',
      targetPath: validTitle,
    );
    var created = false;
    try {
      await Directory(novelRoot).create();
      created = true;
      await Directory(p.join(novelRoot, _metadataDirectoryName)).create();
      await Directory(p.join(novelRoot, _bodyDirectoryName)).create();
      await _writeJsonNew(
        File(_novelManifestPath(novelRoot)),
        _novelToJson(metadata),
      );
      await _writeJsonNew(
        File(_contentManifestPath(novelRoot)),
        _contentToJson(tree),
      );
      await _registerNovel(rootPath, metadata.id, validTitle);
      await _clearPending(rootPath);
      final snapshot = NovelSnapshot(
        rootPath: validTitle,
        metadata: metadata,
        contentTree: tree,
      );
      return NovelStructureMutation(
        snapshot: snapshot,
        entry: _semanticEntry(
          name: validTitle,
          relativePath: validTitle,
          type: LibraryEntryType.directory,
          kind: LibraryEntrySemanticKind.novel,
          semanticId: metadata.id.value,
          novelId: metadata.id.value,
        ),
      );
    } catch (error) {
      if (created) {
        await _deleteDirectorySafely(novelRoot, recursive: true);
      }
      await _clearPending(rootPath);
      if (error is FileSystemException) {
        throw LibraryOperationException(_fileSystemFailure(error));
      }
      rethrow;
    }
  }

  @override
  Future<NovelStructureMutation> registerExistingNovel(
    LibraryAccess access, {
    required String relativePath,
  }) async {
    final rootPath = await _resolveRoot(access);
    final novelRoot = await _resolveExistingDirectory(rootPath, relativePath);
    final normalizedPath = p.relative(novelRoot, from: rootPath);
    if (p.dirname(normalizedPath) != '.') {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.invalidLocation,
          message: '小说目录必须位于书库根级。',
        ),
      );
    }
    final novelFile = File(_novelManifestPath(novelRoot));
    NovelMetadata metadata;
    if (await novelFile.exists()) {
      metadata = _parseNovelMetadata(await _readJsonObject(novelFile));
    } else {
      final bodyPath = p.join(novelRoot, _bodyDirectoryName);
      final bodyType = await FileSystemEntity.type(
        bodyPath,
        followLinks: false,
      );
      if (bodyType == FileSystemEntityType.notFound) {
        await Directory(bodyPath).create();
      } else if (bodyType != FileSystemEntityType.directory) {
        throw const LibraryOperationException(
          LibraryFailure(
            code: LibraryFailureCode.invalidLocation,
            message: '“正文”已存在，但不是文件夹。',
          ),
        );
      }
      final now = _clock.nowUtc();
      metadata = NovelMetadata(
        schemaVersion: _schemaVersion,
        id: NovelId(_idGenerator.generate()),
        title: p.basename(novelRoot),
        description: '',
        coverPath: null,
        body: NovelBody(
          id: ContentId(_idGenerator.generate()),
          relativePath: _bodyDirectoryName,
        ),
        chapterFormat: ChapterFormat.markdown,
        numberingMode: NumberingMode.continuous,
        createdAt: now,
        updatedAt: now,
      );
      await Directory(p.join(novelRoot, _metadataDirectoryName)).create();
      await _writeJsonNew(novelFile, _novelToJson(metadata));
    }

    await _writePending(
      rootPath,
      metadata.id,
      normalizedPath,
      operation: 'registerNovel',
    );
    try {
      final contentFile = File(_contentManifestPath(novelRoot));
      final tree = await contentFile.exists()
          ? _parseContentTree(await _readJsonObject(contentFile))
          : await _scanContentTree(novelRoot, metadata, const []);
      if (tree.novelId != metadata.id) {
        throw const LibraryOperationException(
          LibraryFailure(
            code: LibraryFailureCode.metadataCorrupt,
            message: '小说与正文内容树的 ID 不一致。',
          ),
        );
      }
      if (!await contentFile.exists()) {
        await _writeJsonNew(contentFile, _contentToJson(tree));
      }
      await _registerNovel(rootPath, metadata.id, normalizedPath);
      await _clearPending(rootPath);
      final snapshot = NovelSnapshot(
        rootPath: normalizedPath,
        metadata: metadata,
        contentTree: tree,
      );
      return NovelStructureMutation(
        snapshot: snapshot,
        entry: _semanticEntry(
          name: p.basename(novelRoot),
          relativePath: normalizedPath,
          type: LibraryEntryType.directory,
          kind: LibraryEntrySemanticKind.novel,
          semanticId: metadata.id.value,
          novelId: metadata.id.value,
        ),
      );
    } catch (error) {
      await _clearPending(rootPath);
      if (error is FileSystemException) {
        throw LibraryOperationException(_fileSystemFailure(error));
      }
      rethrow;
    }
  }

  @override
  Future<NovelStructureMutation> renameNovel(
    LibraryAccess access, {
    required NovelId novelId,
    required String newName,
  }) async {
    final rootPath = await _resolveRoot(access);
    final registration = await _registrationFor(rootPath, novelId);
    final snapshot = await _loadNovel(rootPath, registration);
    final validName = _validateName(newName);
    if (validName == snapshot.rootPath) {
      return NovelStructureMutation(
        snapshot: snapshot,
        entry: _semanticEntry(
          name: validName,
          relativePath: snapshot.rootPath,
          type: LibraryEntryType.directory,
          kind: LibraryEntrySemanticKind.novel,
          semanticId: novelId.value,
          novelId: novelId.value,
        ),
      );
    }
    final sourcePath = p.join(rootPath, snapshot.rootPath);
    final targetPath = p.join(rootPath, validName);
    if (await FileSystemEntity.type(targetPath, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw _alreadyExists(validName);
    }
    await _writePending(
      rootPath,
      novelId,
      validName,
      operation: 'renameNovel',
      sourcePath: snapshot.rootPath,
      targetPath: validName,
    );
    await _renameEntity(
      access,
      rootPath,
      sourcePath,
      targetPath,
      FileSystemEntityType.directory,
    );
    final metadata = NovelMetadata(
      schemaVersion: snapshot.metadata.schemaVersion,
      id: snapshot.metadata.id,
      title: validName,
      description: snapshot.metadata.description,
      coverPath: snapshot.metadata.coverPath,
      body: snapshot.metadata.body,
      chapterFormat: snapshot.metadata.chapterFormat,
      numberingMode: snapshot.metadata.numberingMode,
      createdAt: snapshot.metadata.createdAt,
      updatedAt: _clock.nowUtc(),
    );
    await _writeJsonAtomic(
      File(_novelManifestPath(targetPath)),
      _novelToJson(metadata),
    );
    await _updateNovelRegistration(rootPath, novelId, validName);
    await _clearPending(rootPath);
    final updated = NovelSnapshot(
      rootPath: validName,
      metadata: metadata,
      contentTree: snapshot.contentTree,
    );
    return NovelStructureMutation(
      snapshot: updated,
      entry: _semanticEntry(
        name: validName,
        relativePath: validName,
        type: LibraryEntryType.directory,
        kind: LibraryEntrySemanticKind.novel,
        semanticId: novelId.value,
        novelId: novelId.value,
      ),
      pathChanges: [PathChange(oldPath: snapshot.rootPath, newPath: validName)],
    );
  }

  @override
  Future<NovelStructureMutation> renameBody(
    LibraryAccess access, {
    required NovelId novelId,
    required String newName,
  }) async {
    final rootPath = await _resolveRoot(access);
    final snapshot = await _loadNovel(
      rootPath,
      await _registrationFor(rootPath, novelId),
    );
    final validName = _validateName(newName);
    final oldBody = snapshot.metadata.body.relativePath;
    if (validName == oldBody) {
      return NovelStructureMutation(
        snapshot: snapshot,
        entry: _bodyEntry(snapshot),
      );
    }
    final sourcePath = p.join(rootPath, snapshot.rootPath, oldBody);
    final targetPath = p.join(rootPath, snapshot.rootPath, validName);
    if (await FileSystemEntity.type(targetPath, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw _alreadyExists(validName);
    }
    await _writePending(
      rootPath,
      novelId,
      snapshot.rootPath,
      operation: 'renameBody',
      sourcePath: p.join(snapshot.rootPath, oldBody),
      targetPath: p.join(snapshot.rootPath, validName),
    );
    await _renameEntity(
      access,
      rootPath,
      sourcePath,
      targetPath,
      FileSystemEntityType.directory,
    );
    final metadata = NovelMetadata(
      schemaVersion: snapshot.metadata.schemaVersion,
      id: snapshot.metadata.id,
      title: snapshot.metadata.title,
      description: snapshot.metadata.description,
      coverPath: snapshot.metadata.coverPath,
      body: NovelBody(id: snapshot.metadata.body.id, relativePath: validName),
      chapterFormat: snapshot.metadata.chapterFormat,
      numberingMode: snapshot.metadata.numberingMode,
      createdAt: snapshot.metadata.createdAt,
      updatedAt: _clock.nowUtc(),
    );
    final nodes = snapshot.contentTree.nodes
        .map((node) {
          return node.copyWith(
            relativePath: p.join(
              validName,
              p.relative(node.relativePath, from: oldBody),
            ),
          );
        })
        .toList(growable: false);
    final tree = ContentTree(
      schemaVersion: snapshot.contentTree.schemaVersion,
      novelId: novelId,
      revision: snapshot.contentTree.revision + 1,
      nodes: nodes,
    );
    final novelRoot = p.join(rootPath, snapshot.rootPath);
    await _writeJsonAtomic(
      File(_novelManifestPath(novelRoot)),
      _novelToJson(metadata),
    );
    await _writeJsonAtomic(
      File(_contentManifestPath(novelRoot)),
      _contentToJson(tree),
    );
    await _clearPending(rootPath);
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
          oldPath: p.join(snapshot.rootPath, oldBody),
          newPath: p.join(snapshot.rootPath, validName),
        ),
      ],
    );
  }

  @override
  Future<NovelStructureMutation> createVolume(
    LibraryAccess access, {
    required NovelId novelId,
  }) async {
    final rootPath = await _resolveRoot(access);
    final snapshot = await _loadNovel(
      rootPath,
      await _registrationFor(rootPath, novelId),
    );
    var number =
        _maximumNumber(
          snapshot.contentTree.nodes.where(
            (node) => node.type == ContentNodeType.volume,
          ),
        ) +
        1;
    late String name;
    late String targetPath;
    do {
      name = '第${_chineseNumber(number)}卷';
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
      id: ContentId(_idGenerator.generate()),
      type: ContentNodeType.volume,
      parentId: snapshot.metadata.body.id,
      relativePath: p.join(snapshot.metadata.body.relativePath, name),
      order: _nextOrder(
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
    final rootPath = await _resolveRoot(access);
    final snapshot = await _loadNovel(
      rootPath,
      await _registrationFor(rootPath, novelId),
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
    var number = _maximumNumber(candidates) + 1;
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
      id: ContentId(_idGenerator.generate()),
      type: ContentNodeType.chapter,
      parentId: parentId,
      relativePath: p.join(parentPath, name),
      order: _nextOrder(snapshot.contentTree.childrenOf(parentId)),
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
    final rootPath = await _resolveRoot(access);
    final snapshot = await _loadNovel(
      rootPath,
      await _registrationFor(rootPath, novelId),
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
        ? _renamedDocumentName(currentName, newName)
        : _validateName(newName);
    if (validName == currentName) {
      return NovelStructureMutation(
        snapshot: snapshot,
        entry: _entryForContent(snapshot, node),
      );
    }
    final targetPath = p.join(p.dirname(sourcePath), validName);
    if (await FileSystemEntity.type(targetPath, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw _alreadyExists(validName);
    }
    await _writePending(
      rootPath,
      novelId,
      snapshot.rootPath,
      operation: 'renameNode',
      sourcePath: p.join(snapshot.rootPath, node.relativePath),
      targetPath: p.relative(targetPath, from: rootPath),
    );
    await _renameEntity(
      access,
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
    await _clearPending(rootPath);
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
    final rootPath = await _resolveRoot(access);
    final snapshot = await _loadNovel(
      rootPath,
      await _registrationFor(rootPath, novelId),
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
      throw _alreadyExists(p.basename(newRelative));
    }
    await _writePending(
      rootPath,
      novelId,
      snapshot.rootPath,
      operation: 'moveChapter',
      sourcePath: oldLibraryPath,
      targetPath: newLibraryPath,
    );
    await _renameEntity(
      access,
      rootPath,
      p.join(rootPath, oldLibraryPath),
      p.join(rootPath, newLibraryPath),
      FileSystemEntityType.file,
    );
    final moved = chapter.copyWith(
      parentId: parentId,
      relativePath: newRelative,
      order: _nextOrder(snapshot.contentTree.childrenOf(parentId)),
    );
    final nodes = snapshot.contentTree.nodes
        .map((node) => node.id == chapter.id ? moved : node)
        .toList(growable: false);
    final updated = await _writeContentTree(rootPath, snapshot, nodes);
    await _clearPending(rootPath);
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
    final rootPath = await _resolveRoot(access);
    final snapshot = await _loadNovel(
      rootPath,
      await _registrationFor(rootPath, novelId),
    );
    final node = snapshot.contentTree.nodeById(nodeId);
    if (node == null) {
      throw const LibraryOperationException(
        LibraryFailure(code: LibraryFailureCode.notFound, message: '内容不存在。'),
      );
    }
    final siblings = snapshot.contentTree.childrenOf(node.parentId).toList();
    final oldIndex = siblings.indexWhere((item) => item.id == nodeId);
    if (oldIndex < 0 || newIndex < 0 || newIndex >= siblings.length) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.invalidLocation,
          message: '排序位置无效。',
        ),
      );
    }
    final moved = siblings.removeAt(oldIndex);
    siblings.insert(newIndex, moved);
    final orders = <ContentId, int>{
      for (var index = 0; index < siblings.length; index += 1)
        siblings[index].id: (index + 1) * _orderStep,
    };
    final nodes = snapshot.contentTree.nodes
        .map(
          (item) => orders[item.id] == null
              ? item
              : item.copyWith(order: orders[item.id]),
        )
        .toList(growable: false);
    await _writePending(
      rootPath,
      novelId,
      snapshot.rootPath,
      operation: 'reorderNode',
    );
    final updated = await _writeContentTree(rootPath, snapshot, nodes);
    await _clearPending(rootPath);
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
    final rootPath = await _resolveRoot(access);
    final snapshot = await _loadNovel(
      rootPath,
      await _registrationFor(rootPath, novelId),
    );
    final novelRoot = p.join(rootPath, snapshot.rootPath);
    final scanned = await _scanContentTree(
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
        _contentSignature(merged) !=
        _contentSignature(snapshot.contentTree.nodes);
    final updated = changed
        ? await _writeContentTree(rootPath, snapshot, merged)
        : snapshot;
    return NovelReconciliationResult(snapshot: updated, issues: issues);
  }

  @override
  Future<DocumentSnapshot> readDocument(
    LibraryAccess access,
    DocumentRef ref,
  ) async {
    try {
      final rootPath = await _resolveRoot(access);
      final filePath = await _resolveExistingFile(rootPath, ref.relativePath);
      _validateDocumentFormat(filePath, ref.format);
      return _readSnapshot(filePath, ref);
    } on LibraryOperationException {
      rethrow;
    } on FormatException {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.unsupportedEncoding,
          message: '文件不是有效的 UTF-8 文本。',
        ),
      );
    } on FileSystemException catch (error) {
      throw LibraryOperationException(_fileSystemFailure(error));
    }
  }

  @override
  Future<DocumentSaveResult> saveDocument(
    LibraryAccess access, {
    required DocumentSnapshot original,
    required String text,
  }) async {
    String? temporaryPath;
    try {
      final rootPath = await _resolveRoot(access);
      final filePath = await _resolveExistingFile(
        rootPath,
        original.ref.relativePath,
      );
      _validateDocumentFormat(filePath, original.ref.format);
      final current = await _readSnapshot(filePath, original.ref);
      if (current.revision != original.revision) {
        return DocumentSaveConflict(current);
      }

      final bytes = _encodeDocument(original, text);
      final gateway = fileOperationsGateway;
      if (gateway != null) {
        final replaced = await gateway.replaceDocument(
          access,
          relativePath: original.ref.relativePath,
          expectedRevision: original.revision.value,
          bytes: Uint8List.fromList(bytes),
        );
        if (!replaced) {
          return DocumentSaveConflict(
            await _readSnapshot(filePath, original.ref),
          );
        }
        return DocumentSaveSuccess(
          _savedSnapshot(original: original, text: text, bytes: bytes),
        );
      }
      temporaryPath = p.join(
        p.dirname(filePath),
        '.${p.basename(filePath)}.tmp-${_idGenerator.generate()}',
      );
      final temporaryFile = File(temporaryPath);
      await temporaryFile.writeAsBytes(bytes, flush: true);

      final latest = await _readSnapshot(filePath, original.ref);
      if (latest.revision != original.revision) {
        return DocumentSaveConflict(latest);
      }
      await temporaryFile.rename(filePath);
      temporaryPath = null;
      return DocumentSaveSuccess(
        _savedSnapshot(original: original, text: text, bytes: bytes),
      );
    } on LibraryOperationException {
      rethrow;
    } on FormatException {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.unsupportedEncoding,
          message: '文件不是有效的 UTF-8 文本。',
        ),
      );
    } on FileSystemException catch (error) {
      throw LibraryOperationException(_fileSystemFailure(error));
    } finally {
      if (temporaryPath != null) {
        await _deleteFileSafely(temporaryPath);
      }
    }
  }

  @override
  Stream<DocumentChange> watchDocuments(LibraryAccess access) async* {
    final rootPath = await _resolveRoot(access);
    await for (final event in Directory(rootPath).watch(recursive: true)) {
      final relativePath = p.relative(event.path, from: rootPath);
      if (_isHiddenPath(relativePath)) {
        continue;
      }
      final type = switch (event) {
        FileSystemCreateEvent() => DocumentChangeType.created,
        FileSystemDeleteEvent() => DocumentChangeType.deleted,
        FileSystemMoveEvent() => DocumentChangeType.moved,
        _ => DocumentChangeType.modified,
      };
      yield DocumentChange(relativePath: relativePath, type: type);
      if (event case FileSystemMoveEvent(
        :final destination?,
      ) when p.isWithin(rootPath, destination)) {
        yield DocumentChange(
          relativePath: p.relative(destination, from: rootPath),
          type: DocumentChangeType.created,
        );
      }
    }
  }

  Future<String> _resolveRoot(LibraryAccess access) async {
    final directory = Directory(p.normalize(p.absolute(access.token)));
    if (!await directory.exists()) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.notFound,
          message: '书库目录不存在或已被移动。',
        ),
      );
    }
    final rootPath = p.normalize(await directory.resolveSymbolicLinks());
    if (rootPath == p.rootPrefix(rootPath)) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.invalidLocation,
          message: '不能将文件系统根目录设为书库。',
        ),
      );
    }
    return rootPath;
  }

  Future<String> _resolveExistingDirectory(
    String rootPath,
    String relativePath,
  ) async {
    if (relativePath.isNotEmpty && _isHiddenPath(relativePath)) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.invalidLocation,
          message: '不能操作书库内部目录。',
        ),
      );
    }
    final path = await _resolveChildPath(rootPath, relativePath);
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type != FileSystemEntityType.directory) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.notFound,
          message: '目录不存在或已被移动。',
        ),
      );
    }
    return path;
  }

  Future<String> _resolveExistingFile(
    String rootPath,
    String relativePath,
  ) async {
    final path = await _resolveExistingEntity(rootPath, relativePath);
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type != FileSystemEntityType.file) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.notFound,
          message: '文件不存在或已被移动。',
        ),
      );
    }
    return path;
  }

  Future<String> _resolveExistingEntity(
    String rootPath,
    String relativePath,
  ) async {
    if (_isHiddenPath(relativePath)) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.invalidLocation,
          message: '不能操作书库内部文件。',
        ),
      );
    }
    final path = await _resolveChildPath(rootPath, relativePath);
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw const LibraryOperationException(
        LibraryFailure(code: LibraryFailureCode.notFound, message: '文件或目录不存在。'),
      );
    }
    if (type == FileSystemEntityType.link) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.invalidLocation,
          message: '不能操作符号链接。',
        ),
      );
    }
    return path;
  }

  Future<String> _resolveChildPath(String rootPath, String relativePath) async {
    if (p.isAbsolute(relativePath)) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.invalidLocation,
          message: '目录路径超出了书库范围。',
        ),
      );
    }
    final candidate = p.normalize(p.join(rootPath, relativePath));
    if (candidate != rootPath && !p.isWithin(rootPath, candidate)) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.invalidLocation,
          message: '目录路径超出了书库范围。',
        ),
      );
    }

    final candidateType = await FileSystemEntity.type(
      candidate,
      followLinks: false,
    );
    if (candidateType == FileSystemEntityType.link) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.invalidLocation,
          message: '目录路径不能包含符号链接。',
        ),
      );
    }
    if (candidateType == FileSystemEntityType.notFound) {
      return candidate;
    }

    final resolvedCandidate = p.normalize(
      await Directory(candidate).resolveSymbolicLinks(),
    );
    if (resolvedCandidate != rootPath &&
        !p.isWithin(rootPath, resolvedCandidate)) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.invalidLocation,
          message: '目录路径超出了书库范围。',
        ),
      );
    }
    return resolvedCandidate;
  }

  String _manifestPath(String rootPath) {
    return p.join(rootPath, _metadataDirectoryName, _manifestFileName);
  }

  String _validateName(String name) {
    final value = name.trim();
    if (value.isEmpty ||
        value == '.' ||
        value == '..' ||
        value.startsWith('.') ||
        value.contains('/') ||
        value.contains('\\') ||
        value.contains('\u0000')) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.invalidName,
          message: '名称无效，请勿使用空名称、隐藏名称或路径分隔符。',
        ),
      );
    }
    return value;
  }

  String _documentFileName(String name, DocumentFormat format) {
    final value = _validateName(name);
    final extension = switch (format) {
      DocumentFormat.text => '.txt',
      DocumentFormat.markdown => '.md',
    };
    final existingExtension = p.extension(value);
    if (existingExtension.isEmpty) {
      return '$value$extension';
    }
    if (existingExtension.toLowerCase() != extension) {
      throw LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.invalidName,
          message: '文件名必须使用 $extension 扩展名。',
        ),
      );
    }
    return value;
  }

  String _renamedDocumentName(String currentName, String newName) {
    final extension = p.extension(currentName);
    final value = _validateName(newName);
    if (p.extension(value).isNotEmpty) {
      if (p.extension(value).toLowerCase() != extension.toLowerCase()) {
        throw LibraryOperationException(
          LibraryFailure(
            code: LibraryFailureCode.invalidName,
            message: '重命名不能修改 $extension 扩展名。',
          ),
        );
      }
      return value;
    }
    return '$value$extension';
  }

  void _validateDocumentFormat(String filePath, DocumentFormat format) {
    final expected = switch (format) {
      DocumentFormat.text => '.txt',
      DocumentFormat.markdown => '.md',
    };
    if (p.extension(filePath).toLowerCase() != expected) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.unsupportedFormat,
          message: '当前文件格式不支持文本编辑。',
        ),
      );
    }
  }

  Future<DocumentSnapshot> _readSnapshot(
    String filePath,
    DocumentRef ref,
  ) async {
    final bytes = await File(filePath).readAsBytes();
    final hasBom =
        bytes.length >= 3 &&
        bytes[0] == 0xef &&
        bytes[1] == 0xbb &&
        bytes[2] == 0xbf;
    final text = utf8.decode(hasBom ? bytes.sublist(3) : bytes);
    final lineEnding = _lineEnding(text);
    return DocumentSnapshot(
      ref: ref,
      text: lineEnding == LineEnding.crlf
          ? text.replaceAll('\r\n', '\n')
          : text,
      encoding: hasBom ? TextEncoding.utf8Bom : TextEncoding.utf8,
      lineEnding: lineEnding,
      revision: _revision(bytes),
    );
  }

  List<int> _encodeDocument(DocumentSnapshot original, String text) {
    final normalized = switch (original.lineEnding) {
      LineEnding.crlf =>
        text
            .replaceAll('\r\n', '\n')
            .replaceAll('\r', '\n')
            .replaceAll('\n', '\r\n'),
      LineEnding.lf => text.replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
      LineEnding.mixed => text,
    };
    return [
      if (original.encoding == TextEncoding.utf8Bom) ...const [
        0xef,
        0xbb,
        0xbf,
      ],
      ...utf8.encode(normalized),
    ];
  }

  DocumentSnapshot _savedSnapshot({
    required DocumentSnapshot original,
    required String text,
    required List<int> bytes,
  }) {
    return DocumentSnapshot(
      ref: original.ref,
      text: text,
      encoding: original.encoding,
      lineEnding: original.lineEnding,
      revision: _revision(bytes),
    );
  }

  Future<List<LibraryEntry>> _annotateEntries(
    String rootPath,
    String relativePath,
    List<LibraryEntry> entries,
  ) async {
    final manifestFile = File(_manifestPath(rootPath));
    if (!await manifestFile.exists()) {
      return entries;
    }
    final manifest = await _readJsonObject(manifestFile);
    final registrations = _parseNovelRegistrations(manifest['novels']);
    if (relativePath.isEmpty) {
      final novelIdsByPath = <String, NovelId>{};
      for (final registration in registrations) {
        if (!entries.any(
          (entry) => entry.relativePath == registration.relativePath,
        )) {
          continue;
        }
        try {
          final metadata = await _loadNovelMetadata(rootPath, registration);
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
            return _semanticEntry(
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
      snapshot = await _loadNovel(rootPath, registration);
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
            return _semanticEntry(
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
          return _semanticEntry(
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

  Future<ContentTree> _scanContentTree(
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
        return _nextOrder(
          existing.where((node) => node.parentId == parentId).toList(),
        );
      });
      nextOrders[parentId] = next + _orderStep;
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
      for (final entity in await _visibleEntities(directoryPath)) {
        final type = await FileSystemEntity.type(
          entity.path,
          followLinks: false,
        );
        if (type == FileSystemEntityType.file &&
            _isDocumentName(p.basename(entity.path))) {
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
              : _scannedChapter(relativePath, parentId, takeOrder(parentId)),
        );
      }
    }

    final volumeEntities = <FileSystemEntity>[];
    final rootChapterEntities = <FileSystemEntity>[];
    for (final entity in await _visibleEntities(bodyRoot)) {
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        volumeEntities.add(entity);
      } else if (type == FileSystemEntityType.file &&
          _isDocumentName(p.basename(entity.path))) {
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
              id: ContentId(_idGenerator.generate()),
              type: ContentNodeType.volume,
              parentId: metadata.body.id,
              relativePath: relativePath,
              order: takeOrder(metadata.body.id),
              number: _volumeNumber(p.basename(entity.path)),
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
      schemaVersion: _schemaVersion,
      novelId: metadata.id,
      revision: existing.isEmpty ? 0 : 1,
      nodes: nodes,
    );
  }

  Future<List<FileSystemEntity>> _visibleEntities(String path) async {
    try {
      final entities = await Directory(path)
          .list(followLinks: false)
          .where((entity) => !p.basename(entity.path).startsWith('.'))
          .toList();
      entities.sort(
        (left, right) =>
            _naturalCompare(p.basename(left.path), p.basename(right.path)),
      );
      return entities;
    } on FileSystemException catch (error) {
      throw LibraryOperationException(_fileSystemFailure(error));
    }
  }

  ContentNode _scannedChapter(
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
      id: ContentId(_idGenerator.generate()),
      type: ContentNodeType.chapter,
      parentId: parentId,
      relativePath: relativePath,
      order: order,
      number: match == null ? null : int.parse(match.group(1)!),
      role: role,
    );
  }

  int? _volumeNumber(String name) {
    final arabic = RegExp(r'^第(\d+)卷').firstMatch(name);
    if (arabic != null) {
      return int.parse(arabic.group(1)!);
    }
    final chinese = RegExp(r'^第([零一二三四五六七八九十百千]+)卷').firstMatch(name);
    return chinese == null ? null : _parseChineseNumber(chinese.group(1)!);
  }

  bool _isDocumentName(String name) {
    final extension = p.extension(name).toLowerCase();
    return extension == '.txt' || extension == '.md';
  }

  int _nextOrder(List<ContentNode> siblings) {
    return siblings.fold<int>(
          0,
          (value, node) => node.order > value ? node.order : value,
        ) +
        _orderStep;
  }

  int _maximumNumber(Iterable<ContentNode> nodes) {
    return nodes.fold<int>(
      0,
      (value, node) => (node.number ?? 0) > value ? node.number! : value,
    );
  }

  String _contentSignature(List<ContentNode> nodes) {
    final sorted = [...nodes]
      ..sort((left, right) => left.id.value.compareTo(right.id.value));
    return sorted
        .map(
          (node) =>
              '${node.id}:${node.parentId}:${node.relativePath}:${node.order}:${node.number}:${node.role.name}',
        )
        .join('|');
  }

  int _naturalCompare(String left, String right) {
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

  String _chineseNumber(int value) {
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

  int? _parseChineseNumber(String value) {
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

  LibraryEntry _semanticEntry({
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

  Future<NovelRegistration> _registrationFor(
    String rootPath,
    NovelId novelId,
  ) async {
    final manifest = await _readJsonObject(File(_manifestPath(rootPath)));
    for (final registration in _parseNovelRegistrations(manifest['novels'])) {
      if (registration.id == novelId) {
        return registration;
      }
    }
    throw const LibraryOperationException(
      LibraryFailure(code: LibraryFailureCode.notFound, message: '小说未在书库中注册。'),
    );
  }

  Future<NovelSnapshot> _loadNovel(
    String rootPath,
    NovelRegistration registration,
  ) async {
    final metadata = await _loadNovelMetadata(rootPath, registration);
    final novelRoot = p.join(rootPath, registration.relativePath);
    final tree = _parseContentTree(
      await _readJsonObject(File(_contentManifestPath(novelRoot))),
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

  Future<NovelMetadata> _loadNovelMetadata(
    String rootPath,
    NovelRegistration registration,
  ) async {
    final novelRoot = await _resolveExistingDirectory(
      rootPath,
      registration.relativePath,
    );
    final metadata = _parseNovelMetadata(
      await _readJsonObject(File(_novelManifestPath(novelRoot))),
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

  Future<NovelStructureMutation> _createContentEntity(
    LibraryAccess access,
    String rootPath,
    NovelSnapshot snapshot,
    ContentNode node, {
    required bool isDirectory,
  }) async {
    final libraryPath = p.join(snapshot.rootPath, node.relativePath);
    final parentPath = await _resolveExistingDirectory(
      rootPath,
      p.dirname(libraryPath),
    );
    final entityPath = p.join(parentPath, p.basename(libraryPath));
    await _writePending(
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
      await _clearPending(rootPath);
      return NovelStructureMutation(
        snapshot: updated,
        entry: _entryForContent(updated, node),
      );
    } catch (error) {
      if (created) {
        if (isDirectory) {
          await _deleteDirectorySafely(entityPath);
        } else {
          await _deleteFileSafely(entityPath);
        }
      }
      await _clearPending(rootPath);
      if (error is FileSystemException) {
        throw LibraryOperationException(_fileSystemFailure(error));
      }
      rethrow;
    }
  }

  Future<NovelSnapshot> _writeContentTree(
    String rootPath,
    NovelSnapshot snapshot,
    List<ContentNode> nodes,
  ) async {
    final now = _clock.nowUtc();
    final metadata = NovelMetadata(
      schemaVersion: snapshot.metadata.schemaVersion,
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
    await _writeJsonAtomic(
      File(_novelManifestPath(novelRoot)),
      _novelToJson(metadata),
    );
    await _writeJsonAtomic(
      File(_contentManifestPath(novelRoot)),
      _contentToJson(tree),
    );
    return NovelSnapshot(
      rootPath: snapshot.rootPath,
      metadata: metadata,
      contentTree: tree,
    );
  }

  LibraryEntry _entryForContent(NovelSnapshot snapshot, ContentNode node) {
    final libraryPath = p.join(snapshot.rootPath, node.relativePath);
    return _semanticEntry(
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

  LibraryEntry _bodyEntry(NovelSnapshot snapshot) {
    return _semanticEntry(
      name: snapshot.metadata.body.relativePath,
      relativePath: p.join(
        snapshot.rootPath,
        snapshot.metadata.body.relativePath,
      ),
      type: LibraryEntryType.directory,
      kind: LibraryEntrySemanticKind.body,
      semanticId: snapshot.metadata.body.id.value,
      novelId: snapshot.metadata.id.value,
    );
  }

  Future<void> _registerNovel(
    String rootPath,
    NovelId novelId,
    String relativePath,
  ) async {
    final file = File(_manifestPath(rootPath));
    final manifest = await _readJsonObject(file);
    final registrations = _parseNovelRegistrations(manifest['novels']);
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
    manifest['updatedAt'] = _clock.nowUtc().toIso8601String();
    await _writeJsonAtomic(file, manifest);
  }

  Future<void> _updateNovelRegistration(
    String rootPath,
    NovelId novelId,
    String relativePath,
  ) async {
    final file = File(_manifestPath(rootPath));
    final manifest = await _readJsonObject(file);
    final registrations = _parseNovelRegistrations(manifest['novels']);
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
      throw _alreadyExists(relativePath);
    }
    registrations[index] = NovelRegistration(
      id: novelId,
      relativePath: relativePath,
    );
    manifest['novels'] = registrations
        .map((item) => {'id': item.id.value, 'path': item.relativePath})
        .toList(growable: false);
    manifest['updatedAt'] = _clock.nowUtc().toIso8601String();
    await _writeJsonAtomic(file, manifest);
  }

  List<NovelRegistration> _parseNovelRegistrations(Object? value) {
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
          !_isUuid(item['id']! as String)) {
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

  NovelMetadata _parseNovelMetadata(Map<String, Object?> value) {
    final body = value['body'];
    final novelId = value['novelId'];
    final createdAt = value['createdAt'];
    final updatedAt = value['updatedAt'];
    if (value['schemaVersion'] != _schemaVersion ||
        novelId is! String ||
        !_isUuid(novelId) ||
        value['title'] is! String ||
        value['description'] is! String ||
        body is! Map<String, Object?> ||
        body['id'] is! String ||
        !_isUuid(body['id']! as String) ||
        body['path'] is! String ||
        !_isMetadataRelativePath(body['path']! as String) ||
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
      schemaVersion: _schemaVersion,
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

  ContentTree _parseContentTree(Map<String, Object?> value) {
    final novelId = value['novelId'];
    final nodes = value['nodes'];
    if (value['schemaVersion'] != _schemaVersion ||
        novelId is! String ||
        !_isUuid(novelId) ||
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
      schemaVersion: _schemaVersion,
      novelId: NovelId(novelId),
      revision: value['revision']! as int,
      nodes: nodes.map(_parseContentNode).toList(growable: false),
    );
  }

  ContentNode _parseContentNode(Object? value) {
    if (value is! Map<String, Object?> ||
        value['id'] is! String ||
        !_isUuid(value['id']! as String) ||
        value['parentId'] is! String ||
        !_isUuid(value['parentId']! as String) ||
        value['path'] is! String ||
        !_isMetadataRelativePath(value['path']! as String) ||
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

  Map<String, Object?> _novelToJson(NovelMetadata metadata) => {
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

  Map<String, Object?> _contentToJson(ContentTree tree) => {
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

  Future<Map<String, Object?>> _readJsonObject(File file) async {
    try {
      final value = jsonDecode(await file.readAsString());
      if (value is Map<String, Object?>) {
        return value;
      }
      throw const FormatException();
    } on FormatException {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.metadataCorrupt,
          message: '元数据不是有效的 JSON 对象。',
        ),
      );
    } on FileSystemException catch (error) {
      throw LibraryOperationException(_fileSystemFailure(error));
    }
  }

  Future<void> _writeJsonNew(File file, Map<String, Object?> value) async {
    try {
      await file.create(exclusive: true);
      await file.writeAsString(_encodedJson(value), flush: true);
    } on FileSystemException catch (error) {
      throw LibraryOperationException(_fileSystemFailure(error));
    }
  }

  Future<void> _writeJsonAtomic(File file, Map<String, Object?> value) async {
    final temporary = File('${file.path}.tmp-${_idGenerator.generate()}');
    try {
      await temporary.writeAsString(_encodedJson(value), flush: true);
      await temporary.rename(file.path);
    } on FileSystemException catch (error) {
      throw LibraryOperationException(_fileSystemFailure(error));
    } finally {
      await _deleteFileSafely(temporary.path);
    }
  }

  String _encodedJson(Map<String, Object?> value) {
    return '${const JsonEncoder.withIndent('  ').convert(value)}\n';
  }

  String _novelManifestPath(String novelRoot) =>
      p.join(novelRoot, _metadataDirectoryName, _novelManifestFileName);

  String _contentManifestPath(String novelRoot) =>
      p.join(novelRoot, _metadataDirectoryName, _contentManifestFileName);

  String _pendingPath(String rootPath) => p.join(
    rootPath,
    _metadataDirectoryName,
    _recoveryDirectoryName,
    _pendingOperationFileName,
  );

  String _trashRoot(String rootPath) =>
      p.join(rootPath, _metadataDirectoryName, _trashDirectoryName);

  String _trashManifestPath(String rootPath) =>
      p.join(_trashRoot(rootPath), _trashManifestFileName);

  String _trashTokenRoot(String rootPath, String token) =>
      p.join(_trashRoot(rootPath), token);

  /// 计算某原相对路径在回收站内的目标路径。
  /// 绕过 [_isHiddenPath]（它会拒绝 `.lore` 前缀），仅用
  /// [_isMetadataRelativePath] 防穿越，target 必须落在 `.lore/trash` 内。
  String _resolveTrashTarget(
    String rootPath,
    String token,
    String originalRelativePath,
  ) {
    if (!_isMetadataRelativePath(originalRelativePath)) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.invalidLocation,
          message: '回收站目标路径非法。',
        ),
      );
    }
    return p.join(_trashTokenRoot(rootPath, token), originalRelativePath);
  }

  Future<void> _ensureTrashRoot(String rootPath) async {
    try {
      await Directory(_trashRoot(rootPath)).create(recursive: true);
    } on FileSystemException catch (error) {
      throw LibraryOperationException(_fileSystemFailure(error));
    }
  }

  Future<List<TrashItem>> _readTrashManifest(String rootPath) async {
    final file = File(_trashManifestPath(rootPath));
    if (!await file.exists()) {
      return const [];
    }
    try {
      final value = await _readJsonObject(file);
      final items = value['items'];
      if (items is! List<Object?>) {
        return const [];
      }
      return items.map(_parseTrashItem).whereType<TrashItem>().toList();
    } on LibraryOperationException {
      return const [];
    }
  }

  /// 读 manifest 并对账文件系统：扫描 `.lore/trash/` 下未被 manifest 记录的
  /// token 目录（崩溃在移动后、写清单前留下的孤儿），补录为可恢复条目，
  /// 使其可见、可恢复或可 purge。
  Future<List<TrashItem>> _readTrashManifestWithReconcile(
    String rootPath,
  ) async {
    final trashRoot = Directory(_trashRoot(rootPath));
    if (!await trashRoot.exists()) {
      return const [];
    }
    final manifestItems = List<TrashItem>.from(
      await _readTrashManifest(rootPath),
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
      manifestItems.add(await _orphanTrashItem(rootPath, token));
      changed = true;
    }
    if (changed) {
      await _writeTrashManifest(rootPath, manifestItems);
    }
    return manifestItems;
  }

  /// 为孤儿 token 目录生成一个 TrashItem：把目录下第一层条目作为原相对路径，
  /// 按文件移回（无法可靠推断 novel/volume/chapter 语义，因此标记为 entry）。
  Future<TrashItem> _orphanTrashItem(String rootPath, String token) async {
    final tokenRoot = _trashTokenRoot(rootPath, token);
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
      deletedAt: _clock.nowUtc(),
      restorable: original != '(未知)',
    );
  }

  Future<void> _writeTrashManifest(
    String rootPath,
    List<TrashItem> items,
  ) async {
    await _ensureTrashRoot(rootPath);
    final encoded = {
      'schemaVersion': _schemaVersion,
      'items': items.map(_trashItemToJson).toList(),
    };
    await _writeJsonAtomic(File(_trashManifestPath(rootPath)), encoded);
  }

  Future<void> _appendTrashManifest(String rootPath, TrashItem item) async {
    final items = List<TrashItem>.from(await _readTrashManifest(rootPath));
    items.add(item);
    await _writeTrashManifest(rootPath, items);
  }

  Future<void> _removeTrashManifestItem(String rootPath, String token) async {
    final items = await _readTrashManifest(rootPath);
    items.removeWhere((item) => item.token == token);
    await _writeTrashManifest(rootPath, items);
  }

  TrashItem? _parseTrashItem(Object? value) {
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

  Map<String, Object?> _trashItemToJson(TrashItem item) => {
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
  List<ContentNode> _collectSubtree(ContentTree tree, ContentId nodeId) {
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

  Future<void> _moveIntoTrash(
    String rootPath,
    String token,
    String originalRelativePath,
  ) async {
    final source = p.join(rootPath, originalRelativePath);
    final target = _resolveTrashTarget(rootPath, token, originalRelativePath);
    await Directory(p.dirname(target)).create(recursive: true);
    final type = await FileSystemEntity.type(source, followLinks: false);
    try {
      if (type == FileSystemEntityType.directory) {
        await Directory(source).rename(target);
      } else {
        await File(source).rename(target);
      }
    } on FileSystemException catch (error) {
      throw LibraryOperationException(_fileSystemFailure(error));
    }
  }

  @override
  Future<DeletionResult> deleteNode(
    LibraryAccess access, {
    required NovelId novelId,
    required ContentId nodeId,
  }) async {
    final rootPath = await _resolveRoot(access);
    final snapshot = await _loadNovel(
      rootPath,
      await _registrationFor(rootPath, novelId),
    );
    final subtree = _collectSubtree(snapshot.contentTree, nodeId);
    if (subtree.isEmpty) {
      throw const LibraryOperationException(
        LibraryFailure(code: LibraryFailureCode.notFound, message: '节点不存在。'),
      );
    }
    final target = subtree.first;
    final token = _idGenerator.generate();
    final libraryNodePath = p.join(snapshot.rootPath, target.relativePath);

    await _writePending(
      rootPath,
      novelId,
      snapshot.rootPath,
      operation: 'trashNode',
      sourcePath: libraryNodePath,
      targetPath: p.join(
        _metadataDirectoryName,
        _trashDirectoryName,
        token,
        target.relativePath,
      ),
    );
    try {
      await _ensureTrashRoot(rootPath);
      // 只移根节点：卷目录会连带其下章节，避免逐个移动时子项已随目录移走。
      await _moveIntoTrash(
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
      await _writeJsonAtomic(
        File(_contentManifestPath(p.join(rootPath, snapshot.rootPath))),
        _contentToJson(updatedTree),
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
              trashRelativePath: _resolveTrashTarget(
                rootPath,
                token,
                p.join(snapshot.rootPath, node.relativePath),
              ).substring(rootPath.length + 1),
            ),
          )
          .toList();
      await _appendTrashManifest(
        rootPath,
        TrashItem(
          token: token,
          type: target.type == ContentNodeType.volume
              ? TrashItemType.volume
              : TrashItemType.chapter,
          originalRelativePath: libraryNodePath,
          trashRelativePath: _resolveTrashTarget(
            rootPath,
            token,
            libraryNodePath,
          ).substring(rootPath.length + 1),
          novelId: novelId.value,
          nodeId: target.id.value,
          novelRootPath: snapshot.rootPath,
          deletedAt: _clock.nowUtc(),
          restorable: true,
          children: children,
        ),
      );
      await _clearPending(rootPath);
    } on LibraryOperationException {
      await _clearPending(rootPath);
      rethrow;
    } on FileSystemException catch (error) {
      await _clearPending(rootPath);
      throw LibraryOperationException(_fileSystemFailure(error));
    }

    final fresh = await _loadNovel(
      rootPath,
      await _registrationFor(rootPath, novelId),
    );
    return DeletionResult(
      snapshot: fresh,
      trashToken: token,
      removedNodeIds: subtree.map((node) => node.id).toList(),
      pathChanges: [
        PathChange(
          oldPath: libraryNodePath,
          newPath: p.join(
            _metadataDirectoryName,
            _trashDirectoryName,
            token,
            target.relativePath,
          ),
        ),
      ],
    );
  }

  @override
  Future<DeletionResult> deleteNovel(
    LibraryAccess access, {
    required NovelId novelId,
  }) async {
    final rootPath = await _resolveRoot(access);
    final registration = await _registrationFor(rootPath, novelId);
    final token = _idGenerator.generate();

    await _writePending(
      rootPath,
      novelId,
      registration.relativePath,
      operation: 'trashNovel',
      sourcePath: registration.relativePath,
      targetPath: p.join(
        _metadataDirectoryName,
        _trashDirectoryName,
        token,
        registration.relativePath,
      ),
    );
    try {
      await _ensureTrashRoot(rootPath);
      await _moveIntoTrash(rootPath, token, registration.relativePath);
      await _removeNovelRegistration(rootPath, novelId);
      await _appendTrashManifest(
        rootPath,
        TrashItem(
          token: token,
          type: TrashItemType.novel,
          originalRelativePath: registration.relativePath,
          trashRelativePath: _resolveTrashTarget(
            rootPath,
            token,
            registration.relativePath,
          ).substring(rootPath.length + 1),
          novelId: novelId.value,
          novelRootPath: registration.relativePath,
          deletedAt: _clock.nowUtc(),
          restorable: true,
        ),
      );
      await _clearPending(rootPath);
    } on LibraryOperationException {
      await _clearPending(rootPath);
      rethrow;
    } on FileSystemException catch (error) {
      await _clearPending(rootPath);
      throw LibraryOperationException(_fileSystemFailure(error));
    }

    return DeletionResult(
      trashToken: token,
      removedNodeIds: const [],
      pathChanges: [
        PathChange(
          oldPath: registration.relativePath,
          newPath: p.join(
            _metadataDirectoryName,
            _trashDirectoryName,
            token,
            registration.relativePath,
          ),
        ),
      ],
    );
  }

  @override
  Future<DeletionResult> deleteEntry(
    LibraryAccess access, {
    required String relativePath,
  }) async {
    final rootPath = await _resolveRoot(access);
    final entityPath = await _resolveExistingEntity(rootPath, relativePath);
    final normalized = p.relative(entityPath, from: rootPath);
    final token = _idGenerator.generate();

    await _writePending(
      rootPath,
      const NovelId('00000000-0000-4000-8000-000000000000'),
      '',
      operation: 'trashEntry',
      sourcePath: normalized,
      targetPath: p.join(
        _metadataDirectoryName,
        _trashDirectoryName,
        token,
        normalized,
      ),
    );
    try {
      await _ensureTrashRoot(rootPath);
      await _moveIntoTrash(rootPath, token, normalized);
      await _appendTrashManifest(
        rootPath,
        TrashItem(
          token: token,
          type: TrashItemType.entry,
          originalRelativePath: normalized,
          trashRelativePath: _resolveTrashTarget(
            rootPath,
            token,
            normalized,
          ).substring(rootPath.length + 1),
          deletedAt: _clock.nowUtc(),
          restorable: true,
        ),
      );
      await _clearPending(rootPath);
    } on LibraryOperationException {
      await _clearPending(rootPath);
      rethrow;
    } on FileSystemException catch (error) {
      await _clearPending(rootPath);
      throw LibraryOperationException(_fileSystemFailure(error));
    }

    return DeletionResult(
      trashToken: token,
      removedNodeIds: const [],
      pathChanges: [
        PathChange(
          oldPath: normalized,
          newPath: p.join(
            _metadataDirectoryName,
            _trashDirectoryName,
            token,
            normalized,
          ),
        ),
      ],
    );
  }

  @override
  Future<List<TrashItem>> listItems(LibraryAccess access) async {
    final rootPath = await _resolveRoot(access);
    return _readTrashManifestWithReconcile(rootPath);
  }

  @override
  Future<TrashItem> restore(
    LibraryAccess access, {
    required String trashToken,
    RestoreConflictStrategy strategy = RestoreConflictStrategy.rename,
  }) async {
    final rootPath = await _resolveRoot(access);
    final items = await _readTrashManifest(rootPath);
    final index = items.indexWhere((item) => item.token == trashToken);
    if (index < 0) {
      throw const LibraryOperationException(
        LibraryFailure(code: LibraryFailureCode.notFound, message: '回收站条目不存在。'),
      );
    }
    final item = items[index];
    final novelId = item.novelId == null ? null : NovelId(item.novelId!);

    await _writePending(
      rootPath,
      novelId ?? const NovelId('00000000-0000-4000-8000-000000000000'),
      item.novelRootPath ?? '',
      operation: 'restoreItem',
      sourcePath: item.trashRelativePath,
      targetPath: item.originalRelativePath,
    );
    try {
      await _restoreItemFiles(rootPath, item, strategy);
      await _removeTrashManifestItem(rootPath, trashToken);
      await _deleteDirectorySafely(
        _trashTokenRoot(rootPath, trashToken),
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
        await _registerNovel(rootPath, novelId, item.novelRootPath!);
      }
      await _clearPending(rootPath);
    } on LibraryOperationException {
      await _clearPending(rootPath);
      rethrow;
    } on FileSystemException catch (error) {
      await _clearPending(rootPath);
      throw LibraryOperationException(_fileSystemFailure(error));
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
            await _deletePathSafelyRecursive(candidate);
            return candidate;
          case RestoreConflictStrategy.rename:
            return _nextAvailablePath(rootPath, original);
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
      final contentFile = File(_contentManifestPath(novelRoot));
      if (!await contentFile.exists()) {
        return;
      }
      final snapshot = await _loadNovel(
        rootPath,
        NovelRegistration(id: novelId, relativePath: novelRootPath),
      );
      final scanned = await _scanContentTree(
        novelRoot,
        snapshot.metadata,
        snapshot.contentTree.nodes,
      );
      await _writeJsonAtomic(contentFile, _contentToJson(scanned));
    } on LibraryOperationException {
      // 恢复后协调失败不阻断恢复本身；watcher 会再次触发 reconcile。
    }
  }

  String _nextAvailablePath(String rootPath, String original) {
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

  Future<void> _deletePathSafelyRecursive(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      await _deleteDirectorySafely(path, recursive: true);
    } else if (type == FileSystemEntityType.file) {
      await _deleteFileSafely(path);
    }
  }

  @override
  Future<void> purge(LibraryAccess access, {required String trashToken}) async {
    final rootPath = await _resolveRoot(access);
    await _removeTrashManifestItem(rootPath, trashToken);
    await _deleteDirectorySafely(
      _trashTokenRoot(rootPath, trashToken),
      recursive: true,
    );
  }

  @override
  Future<void> empty(LibraryAccess access) async {
    final rootPath = await _resolveRoot(access);
    await _deleteDirectorySafely(_trashRoot(rootPath), recursive: true);
  }

  Future<void> _removeNovelRegistration(
    String rootPath,
    NovelId novelId,
  ) async {
    final file = File(_manifestPath(rootPath));
    final manifest = await _readJsonObject(file);
    final registrations = _parseNovelRegistrations(manifest['novels']);
    manifest['novels'] = registrations
        .where((registration) => registration.id != novelId)
        .map(
          (registration) => {
            'id': registration.id.value,
            'path': registration.relativePath,
          },
        )
        .toList();
    manifest['updatedAt'] = _clock.nowUtc().toIso8601String();
    await _writeJsonAtomic(file, manifest);
  }

  Future<void> _writePending(
    String rootPath,
    NovelId novelId,
    String novelPath, {
    required String operation,
    String? sourcePath,
    String? targetPath,
  }) async {
    final file = File(_pendingPath(rootPath));
    await file.parent.create(recursive: true);
    if (await file.exists()) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.externalModification,
          message: '存在尚未恢复的结构操作，请重新打开书库。',
        ),
      );
    }
    await _writeJsonNew(file, {
      'schemaVersion': _schemaVersion,
      'novelId': novelId.value,
      'novelPath': novelPath,
      'operation': operation,
      'sourcePath': sourcePath,
      'targetPath': targetPath,
      'startedAt': _clock.nowUtc().toIso8601String(),
    });
  }

  Future<void> _clearPending(String rootPath) {
    return _deleteFileSafely(_pendingPath(rootPath));
  }

  Future<void> _recoverPending(String rootPath) async {
    final pendingFile = File(_pendingPath(rootPath));
    if (!await pendingFile.exists()) {
      return;
    }
    final pending = await _readJsonObject(pendingFile);
    final novelIdValue = pending['novelId'];
    final novelPath = pending['novelPath'];
    final operation = pending['operation'];
    final sourcePath = pending['sourcePath'];
    final targetPath = pending['targetPath'];
    // trash/restore 操作的 novelPath 可能为空（删除/恢复普通文件、恢复孤儿），
    // 它们的崩溃恢复不依赖小说 manifest：直接 clearPending，让 watcher、
    // trash 目录对账（listItems）与下次 reconcile 把状态收敛到一致。
    final isTrashOperation = operation == 'trashNode' ||
        operation == 'trashNovel' ||
        operation == 'trashEntry' ||
        operation == 'restoreItem';
    if (novelIdValue is! String ||
        !_isUuid(novelIdValue) ||
        novelPath is! String ||
        (!isTrashOperation && !_isMetadataRelativePath(novelPath)) ||
        operation is! String ||
        (sourcePath != null && sourcePath is! String) ||
        (sourcePath != null &&
            !_isMetadataRelativePath(sourcePath as String)) ||
        (targetPath != null && targetPath is! String) ||
        (targetPath != null &&
            !_isMetadataRelativePath(targetPath as String))) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.metadataCorrupt,
          message: '结构操作恢复记录已损坏。',
        ),
      );
    }
    if (isTrashOperation) {
      await _clearPending(rootPath);
      return;
    }
    final novelRoot = p.join(rootPath, novelPath);
    if (!await Directory(novelRoot).exists()) {
      await _clearPending(rootPath);
      return;
    }
    final novelFile = File(_novelManifestPath(novelRoot));
    if (!await novelFile.exists()) {
      await _clearPending(rootPath);
      return;
    }
    var metadata = _parseNovelMetadata(await _readJsonObject(novelFile));
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
        updatedAt: _clock.nowUtc(),
      );
      await _writeJsonAtomic(novelFile, _novelToJson(metadata));
    }
    final contentFile = File(_contentManifestPath(novelRoot));
    var existing = await contentFile.exists()
        ? _parseContentTree(await _readJsonObject(contentFile)).nodes
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
          updatedAt: _clock.nowUtc(),
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
        await _writeJsonAtomic(novelFile, _novelToJson(metadata));
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
    final scanned = await _scanContentTree(novelRoot, metadata, existing);
    await _writeJsonAtomic(contentFile, _contentToJson(scanned));
    final manifest = await _readJsonObject(File(_manifestPath(rootPath)));
    final registrations = _parseNovelRegistrations(manifest['novels']);
    if (registrations.any((registration) => registration.id == metadata.id)) {
      await _updateNovelRegistration(rootPath, metadata.id, novelPath);
    } else {
      await _registerNovel(rootPath, metadata.id, novelPath);
    }
    await _clearPending(rootPath);
  }

  LineEnding _lineEnding(String text) {
    final withoutCrLf = text.replaceAll('\r\n', '');
    final hasCrLf = text.contains('\r\n');
    final hasOtherBreak =
        withoutCrLf.contains('\n') || withoutCrLf.contains('\r');
    if (hasCrLf && !hasOtherBreak) {
      return LineEnding.crlf;
    }
    if (!hasCrLf && !withoutCrLf.contains('\r')) {
      return LineEnding.lf;
    }
    return LineEnding.mixed;
  }

  DocumentRevision _revision(List<int> bytes) {
    return DocumentRevision(sha256.convert(bytes).toString());
  }

  LibraryEntry _entryForPath(
    String rootPath,
    String entityPath,
    FileSystemEntityType type,
  ) {
    final name = p.basename(entityPath);
    return LibraryEntry(
      name: name,
      relativePath: p.relative(entityPath, from: rootPath),
      type: _entryType(name, type),
    );
  }

  Future<String> _renameEntity(
    LibraryAccess access,
    String rootPath,
    String sourcePath,
    String targetPath,
    FileSystemEntityType type,
  ) async {
    try {
      final gateway = fileOperationsGateway;
      if (gateway != null) {
        await gateway.rename(
          access,
          sourcePath: p.relative(sourcePath, from: rootPath),
          targetPath: p.relative(targetPath, from: rootPath),
        );
        return targetPath;
      }
      if (type == FileSystemEntityType.directory) {
        return (await Directory(sourcePath).rename(targetPath)).path;
      }
      return (await File(sourcePath).rename(targetPath)).path;
    } on FileSystemException catch (error) {
      throw LibraryOperationException(_fileSystemFailure(error));
    }
  }

  Future<String> _renameChangingCase(
    LibraryAccess access,
    String rootPath,
    String sourcePath,
    String targetPath,
    FileSystemEntityType type,
  ) async {
    final temporaryPath = p.join(
      p.dirname(sourcePath),
      '.lore-rename-${_idGenerator.generate()}',
    );
    await _renameEntity(access, rootPath, sourcePath, temporaryPath, type);
    try {
      return await _renameEntity(
        access,
        rootPath,
        temporaryPath,
        targetPath,
        type,
      );
    } on FileSystemException {
      await _renameEntity(access, rootPath, temporaryPath, sourcePath, type);
      rethrow;
    } on LibraryOperationException {
      await _renameEntity(access, rootPath, temporaryPath, sourcePath, type);
      rethrow;
    }
  }

  LibraryOperationException _alreadyExists(String name) {
    return LibraryOperationException(
      LibraryFailure(
        code: LibraryFailureCode.alreadyExists,
        message: '“$name”已存在。',
      ),
    );
  }

  bool _isHiddenPath(String relativePath) {
    return p
        .split(p.normalize(relativePath))
        .any((component) => component.startsWith('.'));
  }

  Map<String, Object?> _toJson(LibraryMetadata metadata) {
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

  LibraryInspectionFailure _corrupt(String message) {
    return LibraryInspectionFailure(
      LibraryFailure(
        code: LibraryFailureCode.metadataCorrupt,
        message: message,
      ),
    );
  }

  LibraryFailure _fileSystemFailure(FileSystemException error) {
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

  bool _isUuid(String value) {
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(value);
  }

  bool _isMetadataRelativePath(String value) {
    return value.isNotEmpty &&
        value != '.' &&
        !p.isAbsolute(value) &&
        !p.split(value).contains('..') &&
        p.normalize(value) == value;
  }

  LibraryEntryType _entryType(String name, FileSystemEntityType type) {
    if (type == FileSystemEntityType.directory) {
      return LibraryEntryType.directory;
    }
    return switch (p.extension(name).toLowerCase()) {
      '.txt' => LibraryEntryType.textFile,
      '.md' => LibraryEntryType.markdownFile,
      _ => LibraryEntryType.otherFile,
    };
  }

  int _compareEntries(LibraryEntry left, LibraryEntry right) {
    if (left.semanticOrder != null && right.semanticOrder != null) {
      return left.semanticOrder!.compareTo(right.semanticOrder!);
    }
    if (left.isDirectory != right.isDirectory) {
      return left.isDirectory ? -1 : 1;
    }
    return left.name.toLowerCase().compareTo(right.name.toLowerCase());
  }

  Future<void> _deleteFileSafely(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException catch (_) {
      return;
    }
  }

  Future<void> _deleteDirectorySafely(
    String path, {
    bool recursive = false,
  }) async {
    try {
      final directory = Directory(path);
      if (await directory.exists()) {
        await directory.delete(recursive: recursive);
      }
    } on FileSystemException catch (_) {
      return;
    }
  }
}
