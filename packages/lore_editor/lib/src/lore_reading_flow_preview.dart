import 'package:flutter/material.dart';

import 'editor_style.dart';
import 'editor_typography.dart';

/// 纯文本阅读流预览：只读、可纵向滚动。
///
/// 把 `.txt` 章节正文以「手机阅读器」样式渲染——逐段排版，段首补两个全角空格
/// 缩进（受 [EditorStyle.firstLineIndent] 控制），段间距随
/// [EditorStyle.paragraphSpacing] × [EditorStyle.fontSize] 缩放，字体 / 字号 /
/// 行高与编辑器同口径（共用 [EditorStyle] / [EditorTypography]），保证同一章节
/// 在编辑态与「读者视角」预览态观感一致。
///
/// [scrollController] 与 [header] 供「跨视图滚动同步」使用：外部传入控制器即可
/// 驱动 / 监听预览的滚动；[header]（如章节标题）作为滚动内容的首个子项随正文
/// 一起滚动，与编辑器「标题作为滚动视口首个 sliver」结构对齐，使按比例同步时
/// 标题↔标题、正文↔正文对齐。
///
/// 与 [LoreMarkdownPreview] 对位：后者渲染 Markdown，本组件渲染纯文本正文，
/// 供手机预览等「读者视角」场景使用。
final class LoreReadingFlowPreview extends StatelessWidget {
  const LoreReadingFlowPreview({
    required this.data,
    required this.style,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    this.scrollController,
    this.header,
    super.key,
  });

  /// 正文文本（章节正文，不含标题行）。
  final String data;

  /// 排版参数：字号 / 行高 / 字体 / 段距 / 首行缩进。
  final EditorStyle style;

  /// 内容内边距。默认横向 20、纵向 8，比编辑器的 52 更窄，适配手机等窄阅读框。
  final EdgeInsetsGeometry padding;

  /// 滚动控制器。传入后由内部 [SingleChildScrollView] 使用，便于外部做滚动
  /// 同步（如手机预览 ↔ 编辑器双向同步）。不传则用默认控制器。
  final ScrollController? scrollController;

  /// 滚动内容的首个子项（如章节标题），随正文一起滚动。可选。
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paragraphStyle =
        EditorTypography.bodyText(style, theme) ??
        DefaultTextStyle.of(context).style;
    final paragraphs = splitParagraphs(data);
    final paragraphGap = style.paragraphSpacing * style.fontSize;
    final indent = style.firstLineIndent ? _fullWidthIndent : '';

    return SingleChildScrollView(
      controller: scrollController,
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?header,
          for (var i = 0; i < paragraphs.length; i++) ...[
            if (i > 0) SizedBox(height: paragraphGap),
            Text(ensureIndent(paragraphs[i], indent), style: paragraphStyle),
          ],
        ],
      ),
    );
  }

  /// 按换行切段，逐行作为独立段落（与中文小说「一行一段」的阅读习惯一致）；
  /// 规范化 CRLF / CR 换行，丢弃空行。对外可见以便测试断言切分结果。
  static List<String> splitParagraphs(String text) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    return normalized
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  /// 段首若无可见缩进，补两个全角空格（与 txt 编辑器新建段落同口径）；段首已有
  /// 全角 / 半角空白则视为用户显式缩进，不再叠加。对外可见以便测试。
  static String ensureIndent(String paragraph, String indent) {
    if (indent.isEmpty) return paragraph;
    if (paragraph.startsWith(indent)) return paragraph;
    final first = paragraph.codeUnitAt(0);
    const space = 0x20; // 半角空格
    const tab = 0x09;
    const ideographicSpace = 0x3000; // 全角空格
    if (first == space || first == tab || first == ideographicSpace) {
      return paragraph;
    }
    return indent + paragraph;
  }

  static const String _fullWidthIndent = '　　';
}
