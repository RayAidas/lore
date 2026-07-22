import 'package:flutter/material.dart';

import 'text_annotation.dart';

/// 把一段文本按 [annotations] 区间切成 [InlineSpan] 子节点列表。
///
/// 返回的是【子节点列表】（不含 base 样式）：调用方负责外层 `TextSpan` 的 `style`
/// （正文排版）与段首缩进等前缀。这样 `SelectableText.rich` 的只读宿主可以自由
/// 组合缩进前缀与本函数产出的着色子节点。
///
/// 每个标注区间套其 [TextAnnotation.background] / [color] / [strikethrough]；
/// 区间之间的未标注文本以无样式 [TextSpan] 透出（继承外层 base）。无视觉、零长度
/// 或越界的标注被忽略。
///
/// **重叠契约（先到先得）**：标注按起点排序后顺序消费，若后一个标注完全落在已消费
/// 区间内（`end <= cursor`），它的样式被**静默丢弃**；若部分重叠，后者头部被截掉。
/// 即先出现的标注胜出。diff 的增删互斥、不会重叠，故无影响；但本函数是公有 API，
/// 未来若有重叠复用场景（如搜索高亮 + 批注叠加），需注意此优先级，或调用方自行去重。
List<InlineSpan> buildAnnotationSpans(
  String text,
  List<TextAnnotation> annotations,
) {
  if (text.isEmpty) return const [];

  // 仅保留有效（有视觉、非零长度、在范围内）的区间，按起点排序。
  final ordered = <TextAnnotation>[];
  for (final a in annotations) {
    if (a.background == null && a.color == null && !a.strikethrough) continue;
    if (a.start >= a.end) continue;
    final s = a.start < 0 ? 0 : (a.start > text.length ? text.length : a.start);
    final e = a.end < 0 ? 0 : (a.end > text.length ? text.length : a.end);
    if (e <= s) continue;
    ordered.add(
      TextAnnotation(
        start: s,
        end: e,
        background: a.background,
        color: a.color,
        strikethrough: a.strikethrough,
      ),
    );
  }
  if (ordered.isEmpty) return [TextSpan(text: text)];
  ordered.sort((x, y) => x.start.compareTo(y.start));

  final spans = <InlineSpan>[];
  var cursor = 0;
  for (final a in ordered) {
    if (a.end <= cursor) continue; // 被前一标注（重叠）完全覆盖，跳过。
    final start = a.start > cursor ? a.start : cursor; // 截掉与前者的重叠头。
    if (start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, start)));
    }
    spans.add(
      TextSpan(
        text: text.substring(start, a.end),
        style: TextStyle(
          backgroundColor: a.background,
          color: a.color,
          decoration: a.strikethrough ? TextDecoration.lineThrough : null,
          decorationColor: a.strikethrough ? a.color : null,
        ),
      ),
    );
    cursor = a.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor)));
  }
  return spans;
}
