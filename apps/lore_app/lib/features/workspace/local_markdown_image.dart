import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// 解析 Markdown 中相对图片引用：相对文档目录拼接到书库根，符号链接安全。
/// 越界或不存在时显示占位图标。
final class LocalMarkdownImage extends StatelessWidget {
  const LocalMarkdownImage({
    required this.libraryRoot,
    required this.documentPath,
    required this.uri,
    required this.width,
    required this.height,
    super.key,
  });

  final String libraryRoot;
  final String documentPath;
  final Uri uri;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    if (uri.hasScheme || uri.path.isEmpty || p.isAbsolute(uri.path)) {
      return _placeholder();
    }
    return FutureBuilder<String?>(
      future: _resolvePath(),
      builder: (context, snapshot) {
        final path = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done || path == null) {
          return _placeholder();
        }
        return Image.file(
          File(path),
          width: width,
          height: height,
          errorBuilder: (context, error, stackTrace) => _placeholder(),
        );
      },
    );
  }

  Future<String?> _resolvePath() async {
    try {
      final root = p.normalize(
        await Directory(libraryRoot).resolveSymbolicLinks(),
      );
      final candidate = p.normalize(
        p.join(root, p.dirname(documentPath), uri.path),
      );
      if (!p.isWithin(root, candidate)) {
        return null;
      }
      final type = await FileSystemEntity.type(candidate, followLinks: false);
      if (type != FileSystemEntityType.file) {
        return null;
      }
      final resolved = p.normalize(
        await File(candidate).resolveSymbolicLinks(),
      );
      return p.isWithin(root, resolved) ? resolved : null;
    } on FileSystemException {
      return null;
    }
  }

  Widget _placeholder() {
    return Tooltip(
      message: uri.toString(),
      child: const Icon(Icons.image_not_supported_outlined),
    );
  }
}
