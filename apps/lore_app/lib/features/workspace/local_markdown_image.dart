import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lore_application/lore_application.dart';

/// 解析 Markdown 中相对图片引用：相对文档目录拼接到书库根，符号链接安全。
/// 越界或不存在时显示占位图标。
final class LocalMarkdownImage extends StatelessWidget {
  const LocalMarkdownImage({
    required this.session,
    required this.assetService,
    required this.documentPath,
    required this.uri,
    required this.width,
    required this.height,
    super.key,
  });

  final LibrarySession session;
  final LibraryAssetService assetService;
  final String documentPath;
  final Uri uri;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    if (uri.hasScheme || uri.path.isEmpty || uri.path.startsWith('/')) {
      return _placeholder();
    }
    return FutureBuilder<Uint8List?>(
      future: assetService.readRelative(
        session,
        documentPath: documentPath,
        relativeReference: uri.path,
      ),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done || bytes == null) {
          return _placeholder();
        }
        return Image.memory(
          bytes,
          width: width,
          height: height,
          errorBuilder: (context, error, stackTrace) => _placeholder(),
        );
      },
    );
  }

  Widget _placeholder() {
    return Tooltip(
      message: uri.toString(),
      child: const Icon(Icons.image_not_supported_outlined),
    );
  }
}
