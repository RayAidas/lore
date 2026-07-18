import 'dart:convert';
import 'dart:io';

import 'package:lore_application/lore_application.dart';

/// 通用 JSON / 文件系统 IO 帮手，封装了错误映射、原子写入、安全删除等行为。
///
/// 所有方法都按原 [LocalDirectoryLibraryRepository] 中的实现逐字搬迁；
/// 唯一区别是依赖项通过构造函数注入。
final class LibraryStorageIo {
  const LibraryStorageIo(this.idGenerator);

  final IdGenerator idGenerator;

  Future<Map<String, Object?>> readJsonObject(File file) async {
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
      throw LibraryOperationException(fileSystemFailure(error));
    }
  }

  Future<void> writeJsonNew(File file, Map<String, Object?> value) async {
    try {
      await file.create(exclusive: true);
      await file.writeAsString(encodedJson(value), flush: true);
    } on FileSystemException catch (error) {
      throw LibraryOperationException(fileSystemFailure(error));
    }
  }

  Future<void> writeJsonAtomic(File file, Map<String, Object?> value) async {
    final temporary = File('${file.path}.tmp-${idGenerator.generate()}');
    try {
      await temporary.writeAsString(encodedJson(value), flush: true);
      await temporary.rename(file.path);
    } on FileSystemException catch (error) {
      throw LibraryOperationException(fileSystemFailure(error));
    } finally {
      await deleteFileSafely(temporary.path);
    }
  }

  String encodedJson(Map<String, Object?> value) {
    return '${const JsonEncoder.withIndent('  ').convert(value)}\n';
  }

  Future<void> deleteFileSafely(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException catch (_) {
      return;
    }
  }

  Future<void> deleteDirectorySafely(
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

  Future<void> deletePathSafelyRecursive(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      await deleteDirectorySafely(path, recursive: true);
    } else if (type == FileSystemEntityType.file) {
      await deleteFileSafely(path);
    }
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

  LibraryOperationException alreadyExists(String name) {
    return LibraryOperationException(
      LibraryFailure(
        code: LibraryFailureCode.alreadyExists,
        message: '“$name”已存在。',
      ),
    );
  }

  bool isUuid(String value) {
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(value);
  }
}
