import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:path/path.dart' as p;

final class LocalDirectoryLibraryRepository
    implements LibraryRepository, LibraryTreeRepository, DocumentRepository {
  const LocalDirectoryLibraryRepository({
    required this._idGenerator,
    required this._clock,
    this.fileOperationsGateway,
  });

  static const _schemaVersion = 1;
  static const _metadataDirectoryName = '.lore';
  static const _manifestFileName = 'library.json';

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

      final value = jsonDecode(await manifest.readAsString());
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

      return LibraryInspectionReady(
        LibraryMetadata(
          schemaVersion: schemaVersion,
          id: LibraryId(libraryId),
          createdAt: created.toUtc(),
          updatedAt: updated.toUtc(),
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
      entries.sort(_compareEntries);
      return entries;
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
      'novels': <Object?>[],
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
}
