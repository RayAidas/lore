import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// Markdown 预览：只读、可选中。字体 / 字号 / 行高通过参数与 txt 编辑器对齐，
/// 保证同一篇小说在编辑态与预览态观感一致。
final class LoreMarkdownPreview extends StatelessWidget {
  const LoreMarkdownPreview({
    required this.data,
    this.imageBuilder,
    this.fontFamily,
    this.fontFamilyFallback,
    this.fontSize = 15,
    this.lineHeight = 1.5,
    super.key,
  });

  final String data;
  final Widget Function(Uri uri, double? width, double? height)? imageBuilder;

  /// 正文字体 family（null = 跟随主题默认）。与 txt 编辑器共用同一解析结果。
  final String? fontFamily;

  /// 字体 fallback 链，与 txt 编辑器保持一致。
  final List<String>? fontFamilyFallback;

  /// 正文字号，默认与编辑器 [EditorStyle.defaults] 对齐。
  final double fontSize;

  /// 正文行高。
  final double lineHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyLarge ?? const TextStyle();
    final paragraph = base.copyWith(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      fontSize: fontSize,
      height: lineHeight,
    );
    // 仅把字体 family 注入标题与强调，保留各自字号字重；代码块保持等宽。
    final inherit = TextStyle(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
    );
    final textTheme = theme.textTheme;
    final styleSheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: paragraph,
      h1: textTheme.headlineMedium?.merge(inherit),
      h2: textTheme.headlineSmall?.merge(inherit),
      h3: textTheme.titleLarge?.merge(inherit),
      h4: textTheme.titleMedium?.merge(inherit),
      h5: textTheme.titleSmall?.merge(inherit),
      h6: textTheme.titleSmall?.merge(inherit),
      blockquote: paragraph.copyWith(color: theme.colorScheme.onSurfaceVariant),
      strong: paragraph.copyWith(fontWeight: FontWeight.bold),
      em: paragraph.copyWith(fontStyle: FontStyle.italic),
      // 链接 / 表格 / 列表标记同样走正文字体，避免段内混字体；代码块保持等宽。
      a: paragraph.copyWith(color: Colors.blue),
      tableHead: paragraph.copyWith(fontWeight: FontWeight.w600),
      tableBody: paragraph,
      listBullet: paragraph,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth > 900 ? 900.0 : constraints.maxWidth;
        return Center(
          child: SizedBox(
            width: width,
            height: constraints.maxHeight,
            child: Markdown(
              data: data,
              selectable: true,
              padding: const EdgeInsets.symmetric(horizontal: 52, vertical: 42),
              styleSheet: styleSheet,
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
            ),
          ),
        );
      },
    );
  }
}
