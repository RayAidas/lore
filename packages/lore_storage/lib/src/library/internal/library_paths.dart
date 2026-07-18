import 'package:lore_application/lore_application.dart';
import 'package:path/path.dart' as p;

/// 书库与小说元数据的路径常量与路径计算。
///
/// 这是 [LocalDirectoryLibraryRepository] 内部使用的纯函数集合，
/// 不持有任何状态，不执行文件系统操作。
final class LibraryPaths {
  const LibraryPaths();

  static const schemaVersion = 1;
  static const metadataDirectoryName = '.lore';
  static const manifestFileName = 'library.json';
  static const novelManifestFileName = 'novel.json';
  static const contentManifestFileName = 'content.json';
  static const bodyDirectoryName = '正文';
  static const orderStep = 1000;
  static const recoveryDirectoryName = 'recovery';
  static const trashDirectoryName = 'trash';
  static const pendingOperationFileName = 'pending-operation.json';
  static const trashManifestFileName = 'index.json';

  String manifestPath(String rootPath) =>
      p.join(rootPath, metadataDirectoryName, manifestFileName);

  String novelManifestPath(String novelRoot) =>
      p.join(novelRoot, metadataDirectoryName, novelManifestFileName);

  String contentManifestPath(String novelRoot) =>
      p.join(novelRoot, metadataDirectoryName, contentManifestFileName);

  String pendingPath(String rootPath) => p.join(
    rootPath,
    metadataDirectoryName,
    recoveryDirectoryName,
    pendingOperationFileName,
  );

  String trashRoot(String rootPath) =>
      p.join(rootPath, metadataDirectoryName, trashDirectoryName);

  String trashManifestPath(String rootPath) =>
      p.join(trashRoot(rootPath), trashManifestFileName);

  String trashTokenRoot(String rootPath, String token) =>
      p.join(trashRoot(rootPath), token);

  /// 计算某原相对路径在回收站内的目标路径。
  /// 绕过 [isHiddenPath]（它会拒绝 `.lore` 前缀），仅用
  /// [isMetadataRelativePath] 防穿越，target 必须落在 `.lore/trash` 内。
  String resolveTrashTarget(
    String rootPath,
    String token,
    String originalRelativePath,
  ) {
    if (!isMetadataRelativePath(originalRelativePath)) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.invalidLocation,
          message: '回收站目标路径非法。',
        ),
      );
    }
    return p.join(trashTokenRoot(rootPath, token), originalRelativePath);
  }

  bool isHiddenPath(String relativePath) {
    return p
        .split(p.normalize(relativePath))
        .any((component) => component.startsWith('.'));
  }

  bool isMetadataRelativePath(String value) {
    return value.isNotEmpty &&
        value != '.' &&
        !p.isAbsolute(value) &&
        !p.split(value).contains('..') &&
        p.normalize(value) == value;
  }
}
