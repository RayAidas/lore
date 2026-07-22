import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 管理用户选择的背景图副本。只保存应用私有目录中的文件，原图之后移动或删除
/// 不会影响设置。
final class BackgroundImageStorage {
  BackgroundImageStorage({Future<Directory> Function()? supportDirectory})
    : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  static final shared = BackgroundImageStorage();

  final Future<Directory> Function() _supportDirectory;

  Future<String> importImage(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('所选图片已不存在', sourcePath);
    }
    final directory = await _directory();
    await directory.create(recursive: true);
    final extension = p.extension(source.path).toLowerCase();
    final suffix = extension.isEmpty ? '.img' : extension;
    final destination = File(
      p.join(
        directory.path,
        'background-${DateTime.now().microsecondsSinceEpoch}$suffix',
      ),
    );
    await source.copy(destination.path);
    return destination.path;
  }

  Future<void> deleteManagedImage(String? path) async {
    if (path == null || path.isEmpty) {
      return;
    }
    final directory = await _directory();
    final normalizedDirectory = p.normalize(directory.path);
    final normalizedPath = p.normalize(path);
    if (!p.isWithin(normalizedDirectory, normalizedPath)) {
      return;
    }
    final file = File(normalizedPath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<Directory> _directory() async {
    final supportDirectory = await _supportDirectory();
    return Directory(p.join(supportDirectory.path, 'backgrounds'));
  }
}
