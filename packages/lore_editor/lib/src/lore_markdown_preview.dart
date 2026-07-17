import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

final class LoreMarkdownPreview extends StatelessWidget {
  const LoreMarkdownPreview({required this.data, this.imageBuilder, super.key});

  final String data;
  final Widget Function(Uri uri, double? width, double? height)? imageBuilder;

  @override
  Widget build(BuildContext context) {
    return Markdown(
      data: data,
      selectable: true,
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
      sizedImageBuilder: (config) {
        final builder = imageBuilder;
        if (builder != null) {
          return builder(config.uri, config.width, config.height);
        }
        return Tooltip(
          message: config.uri.toString(),
          child: const Icon(Icons.image_not_supported_outlined),
        );
      },
    );
  }
}
