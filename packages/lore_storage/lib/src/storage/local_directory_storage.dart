import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:path/path.dart' as p;

final class LocalDirectoryStorageFactory implements LibraryStorageFactory {
  const LocalDirectoryStorageFactory({this.fileOperationsGateway});

  final LibraryFileOperationsGateway? fileOperationsGateway;

  @override
  Future<LibraryStorageSession> open(LibraryAccess access) async {
    if (access.backend != LibraryBackendKind.localDirectory) {
      throw ArgumentError.value(access.backend, 'access.backend');
    }
    final root = Directory(p.normalize(p.absolute(access.token)));
    if (!await root.exists()) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.notFound,
          message: '书库目录不存在或已被移动。',
        ),
      );
    }
    final resolvedRoot = p.normalize(await root.resolveSymbolicLinks());
    return LocalDirectoryStorageSession(
      access: access,
      rootPath: resolvedRoot,
      fileOperationsGateway: fileOperationsGateway,
    );
  }
}

final class LocalDirectoryStorageSession implements LibraryStorageSession {
  const LocalDirectoryStorageSession({
    required this.access,
    required this.rootPath,
    this.fileOperationsGateway,
  });

  final LibraryAccess access;
  final String rootPath;
  final LibraryFileOperationsGateway? fileOperationsGateway;

  @override
  StorageCapabilities get capabilities => StorageCapabilities(
    atomicReplace: fileOperationsGateway != null,
    move: true,
    rename: true,
    watch: true,
    caseSensitive: !Platform.isMacOS && !Platform.isWindows,
  );

  @override
  Future<List<StorageEntry>> list(LogicalPath directory) async {
    final path = await _resolve(directory, mustExist: true);
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw _invalidLocation('目标不是目录。');
    }
    final result = <StorageEntry>[];
    await for (final entity in Directory(path).list(followLinks: false)) {
      if (await FileSystemEntity.type(entity.path, followLinks: false) ==
          FileSystemEntityType.link) {
        continue;
      }
      final relative = LogicalPath.parse(
        p.relative(entity.path, from: rootPath),
      );
      final entry = await stat(relative);
      if (entry != null) {
        result.add(entry);
      }
    }
    return result;
  }

  @override
  Future<StorageEntry?> stat(LogicalPath path) async {
    final resolved = await _resolve(path, mustExist: false);
    final type = await FileSystemEntity.type(resolved, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return null;
    }
    if (type == FileSystemEntityType.link) {
      throw _invalidLocation('不能操作符号链接。');
    }
    if (type == FileSystemEntityType.directory) {
      return StorageEntry(
        path: path,
        type: StorageEntryType.directory,
        size: null,
        revision: null,
      );
    }
    if (type != FileSystemEntityType.file) {
      return null;
    }
    final bytes = await File(resolved).readAsBytes();
    return StorageEntry(
      path: path,
      type: StorageEntryType.file,
      size: bytes.length,
      revision: sha256.convert(bytes).toString(),
    );
  }

  @override
  Future<Uint8List> readBytes(LogicalPath path) async {
    final resolved = await _resolve(path, mustExist: true);
    return File(resolved).readAsBytes();
  }

  @override
  Future<void> createDirectory(LogicalPath path) async {
    await _ensureMissing(path);
    final resolved = await _resolve(path, mustExist: false);
    await Directory(resolved).create();
  }

  @override
  Future<void> createFile(LogicalPath path, Uint8List bytes) async {
    await _ensureMissing(path);
    final resolved = await _resolve(path, mustExist: false);
    final file = await File(resolved).create(exclusive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<StorageReplaceResult> replaceFile(
    LogicalPath path, {
    required String expectedRevision,
    required Uint8List bytes,
  }) async {
    final current = await stat(path);
    if (current?.revision != expectedRevision) {
      return StorageReplaceConflict(current?.revision);
    }
    final gateway = fileOperationsGateway;
    if (gateway != null) {
      final replaced = await gateway.replaceDocument(
        access,
        relativePath: path.value,
        expectedRevision: expectedRevision,
        bytes: bytes,
      );
      if (!replaced) {
        return StorageReplaceConflict((await stat(path))?.revision);
      }
      return StorageReplaceSuccess(sha256.convert(bytes).toString());
    }
    final resolved = await _resolve(path, mustExist: true);
    final temporary = File(
      '$resolved.tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      if ((await stat(path))?.revision != expectedRevision) {
        return StorageReplaceConflict((await stat(path))?.revision);
      }
      await temporary.rename(resolved);
      return StorageReplaceSuccess(sha256.convert(bytes).toString());
    } finally {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  @override
  Future<void> move(LogicalPath source, LogicalPath target) async {
    final changesOnlyCase =
        !capabilities.caseSensitive &&
        source.parent == target.parent &&
        source.name.toLowerCase() == target.name.toLowerCase() &&
        source.name != target.name;
    if (changesOnlyCase) {
      final sourcePath = await _resolve(source, mustExist: true);
      final targetPath = await _resolve(target, mustExist: false);
      final gateway = fileOperationsGateway;
      if (gateway != null) {
        await gateway.rename(
          access,
          sourcePath: source.value,
          targetPath: target.value,
        );
        return;
      }
      final temporary = target.parent!.child(
        '.lore-case-${DateTime.now().microsecondsSinceEpoch}',
      );
      final temporaryPath = await _resolve(temporary, mustExist: false);
      final type = await FileSystemEntity.type(sourcePath, followLinks: false);
      if (type != FileSystemEntityType.directory &&
          type != FileSystemEntityType.file) {
        throw _invalidLocation('源文件不存在。');
      }
      var movedToTemporary = false;
      try {
        await _renameEntity(type, sourcePath, temporaryPath);
        movedToTemporary = true;
        await _renameEntity(type, temporaryPath, targetPath);
      } on Object catch (error, stackTrace) {
        if (movedToTemporary &&
            await FileSystemEntity.type(temporaryPath, followLinks: false) !=
                FileSystemEntityType.notFound) {
          try {
            await _renameEntity(type, temporaryPath, sourcePath);
          } on Object {
            Error.throwWithStackTrace(error, stackTrace);
          }
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
      return;
    }
    await _ensureMissing(target);
    final sourcePath = await _resolve(source, mustExist: true);
    final targetPath = await _resolve(target, mustExist: false);
    final gateway = fileOperationsGateway;
    if (gateway != null && source.parent == target.parent) {
      await gateway.rename(
        access,
        sourcePath: source.value,
        targetPath: target.value,
      );
      return;
    }
    final type = await FileSystemEntity.type(sourcePath, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      await Directory(sourcePath).rename(targetPath);
    } else if (type == FileSystemEntityType.file) {
      await File(sourcePath).rename(targetPath);
    } else {
      throw _invalidLocation('源文件不存在。');
    }
  }

  @override
  Future<void> copy(LogicalPath source, LogicalPath target) async {
    await _ensureMissing(target);
    final sourcePath = await _resolve(source, mustExist: true);
    final targetPath = await _resolve(target, mustExist: false);
    final type = await FileSystemEntity.type(sourcePath, followLinks: false);
    if (type == FileSystemEntityType.file) {
      await File(sourcePath).copy(targetPath);
      return;
    }
    if (type != FileSystemEntityType.directory) {
      throw _invalidLocation('源文件不存在。');
    }
    await Directory(targetPath).create();
    await for (final entity in Directory(sourcePath).list(followLinks: false)) {
      final name = p.basename(entity.path);
      await copy(source.child(name), target.child(name));
    }
  }

  @override
  Future<void> delete(LogicalPath path, {required bool recursive}) async {
    final resolved = await _resolve(path, mustExist: true);
    final type = await FileSystemEntity.type(resolved, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      await Directory(resolved).delete(recursive: recursive);
    } else if (type == FileSystemEntityType.file) {
      await File(resolved).delete();
    }
  }

  @override
  Stream<StorageChange> watch() async* {
    await for (final event in Directory(rootPath).watch(recursive: true)) {
      final path = LogicalPath.parse(p.relative(event.path, from: rootPath));
      final type = switch (event) {
        FileSystemCreateEvent() => StorageChangeType.created,
        FileSystemDeleteEvent() => StorageChangeType.deleted,
        FileSystemMoveEvent() => StorageChangeType.moved,
        _ => StorageChangeType.modified,
      };
      final destination =
          event is FileSystemMoveEvent && event.destination != null
          ? LogicalPath.parse(p.relative(event.destination!, from: rootPath))
          : null;
      yield StorageChange(path: path, type: type, destination: destination);
    }
  }

  Future<void> _ensureMissing(LogicalPath path) async {
    if (path.isRoot || await stat(path) != null) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.alreadyExists,
          message: '目标名称已存在。',
        ),
      );
    }
    final parent = path.parent;
    final parentEntry = parent == null ? null : await stat(parent);
    if (parentEntry == null || parentEntry.type != StorageEntryType.directory) {
      throw _invalidLocation('目标父目录不存在。');
    }
  }

  Future<void> _renameEntity(
    FileSystemEntityType type,
    String source,
    String target,
  ) async {
    if (type == FileSystemEntityType.directory) {
      await Directory(source).rename(target);
    } else {
      await File(source).rename(target);
    }
  }

  Future<String> _resolve(LogicalPath path, {required bool mustExist}) async {
    final candidate = path.isRoot
        ? rootPath
        : p.normalize(p.joinAll([rootPath, ...path.value.split('/')]));
    if (candidate != rootPath && !p.isWithin(rootPath, candidate)) {
      throw _invalidLocation('路径超出了书库范围。');
    }
    final type = await FileSystemEntity.type(candidate, followLinks: false);
    if (type == FileSystemEntityType.link) {
      throw _invalidLocation('不能操作符号链接。');
    }
    if (mustExist && type == FileSystemEntityType.notFound) {
      throw const LibraryOperationException(
        LibraryFailure(code: LibraryFailureCode.notFound, message: '文件或目录不存在。'),
      );
    }
    if (type != FileSystemEntityType.notFound) {
      final resolved = p.normalize(
        type == FileSystemEntityType.directory
            ? await Directory(candidate).resolveSymbolicLinks()
            : await File(candidate).resolveSymbolicLinks(),
      );
      if (resolved != rootPath && !p.isWithin(rootPath, resolved)) {
        throw _invalidLocation('路径超出了书库范围。');
      }
    }
    return candidate;
  }

  LibraryOperationException _invalidLocation(String message) {
    return LibraryOperationException(
      LibraryFailure(
        code: LibraryFailureCode.invalidLocation,
        message: message,
      ),
    );
  }
}
