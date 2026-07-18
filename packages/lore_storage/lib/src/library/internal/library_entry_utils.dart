import 'dart:io';

import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:path/path.dart' as p;

import 'library_paths.dart';
import 'library_storage_io.dart';

/// [LibraryEntry] 与文件名 / 路径相关的纯函数与小工具。
///
/// 名称校验、扩展名处理、条目构造、目录排序与大小写改名都在这里。
/// 方法按原 [LocalDirectoryLibraryRepository] 中的实现逐字搬迁。
final class LibraryEntryUtils {
  const LibraryEntryUtils({required this.paths, required this.io});

  final LibraryPaths paths;
  final LibraryStorageIo io;

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

  LibraryEntry entryForPath(
    String rootPath,
    String entityPath,
    FileSystemEntityType type,
  ) {
    final name = p.basename(entityPath);
    return LibraryEntry(
      name: name,
      relativePath: p.relative(entityPath, from: rootPath),
      type: entryType(name, type),
    );
  }

  LibraryEntryType entryType(String name, FileSystemEntityType type) {
    if (type == FileSystemEntityType.directory) {
      return LibraryEntryType.directory;
    }
    return switch (p.extension(name).toLowerCase()) {
      '.txt' => LibraryEntryType.textFile,
      '.md' => LibraryEntryType.markdownFile,
      _ => LibraryEntryType.otherFile,
    };
  }

  int compareEntries(LibraryEntry left, LibraryEntry right) {
    if (left.semanticOrder != null && right.semanticOrder != null) {
      return left.semanticOrder!.compareTo(right.semanticOrder!);
    }
    if (left.isDirectory != right.isDirectory) {
      return left.isDirectory ? -1 : 1;
    }
    return left.name.toLowerCase().compareTo(right.name.toLowerCase());
  }

  String validateName(String name) {
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

  String documentFileName(String name, DocumentFormat format) {
    final value = validateName(name);
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

  String renamedDocumentName(String currentName, String newName) {
    final extension = p.extension(currentName);
    final value = validateName(newName);
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

  Future<String> renameEntity(
    LibraryAccess access,
    LibraryFileOperationsGateway? gateway,
    String rootPath,
    String sourcePath,
    String targetPath,
    FileSystemEntityType type,
  ) async {
    try {
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
      throw LibraryOperationException(io.fileSystemFailure(error));
    }
  }

  Future<String> renameChangingCase(
    LibraryAccess access,
    LibraryFileOperationsGateway? gateway,
    IdGenerator idGenerator,
    String rootPath,
    String sourcePath,
    String targetPath,
    FileSystemEntityType type,
  ) async {
    final temporaryPath = p.join(
      p.dirname(sourcePath),
      '.lore-rename-${idGenerator.generate()}',
    );
    await renameEntity(
      access,
      gateway,
      rootPath,
      sourcePath,
      temporaryPath,
      type,
    );
    try {
      return await renameEntity(
        access,
        gateway,
        rootPath,
        temporaryPath,
        targetPath,
        type,
      );
    } on FileSystemException {
      await renameEntity(
        access,
        gateway,
        rootPath,
        temporaryPath,
        sourcePath,
        type,
      );
      rethrow;
    } on LibraryOperationException {
      await renameEntity(
        access,
        gateway,
        rootPath,
        temporaryPath,
        sourcePath,
        type,
      );
      rethrow;
    }
  }

  LibraryInspectionFailure corrupt(String message) {
    return LibraryInspectionFailure(
      LibraryFailure(
        code: LibraryFailureCode.metadataCorrupt,
        message: message,
      ),
    );
  }
}
