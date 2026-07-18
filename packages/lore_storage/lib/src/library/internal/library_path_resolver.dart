import 'dart:io';

import 'package:lore_application/lore_application.dart';
import 'package:path/path.dart' as p;

import 'library_paths.dart';

/// 书库根路径与相对路径的解析逻辑。
///
/// 每个解析方法都严格按原 [LocalDirectoryLibraryRepository] 中的实现逐字搬迁，
/// 保留了符号链接检查、路径越界检查以及错误信息。
final class LibraryPathResolver {
  const LibraryPathResolver(this.paths);

  final LibraryPaths paths;

  Future<String> resolveRoot(LibraryAccess access) async {
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

  Future<String> resolveExistingDirectory(
    String rootPath,
    String relativePath,
  ) async {
    if (relativePath.isNotEmpty && paths.isHiddenPath(relativePath)) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.invalidLocation,
          message: '不能操作书库内部目录。',
        ),
      );
    }
    final path = await resolveChildPath(rootPath, relativePath);
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

  Future<String> resolveExistingFile(
    String rootPath,
    String relativePath,
  ) async {
    final path = await resolveExistingEntity(rootPath, relativePath);
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

  Future<String> resolveExistingEntity(
    String rootPath,
    String relativePath,
  ) async {
    if (paths.isHiddenPath(relativePath)) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.invalidLocation,
          message: '不能操作书库内部文件。',
        ),
      );
    }
    final path = await resolveChildPath(rootPath, relativePath);
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

  Future<String> resolveChildPath(String rootPath, String relativePath) async {
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
}
