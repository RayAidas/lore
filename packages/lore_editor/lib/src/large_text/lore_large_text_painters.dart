part of 'lore_large_text_editor.dart';

final class _BlockSelectionPainter extends CustomPainter {
  _BlockSelectionPainter({
    required this.text,
    required this.style,
    required this.selection,
    required this.color,
    required this.textDirection,
    required this.textScaler,
    required this.layoutFor,
  });

  final String text;
  // style/textDirection/textScaler 现在只用于 shouldRepaint 的比较——paint
  // 不再自己 layout，而是通过 [layoutFor] 借用 state 缓存的已 layout painter。
  final TextStyle? style;
  final TextSelection selection;
  final Color color;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final TextPainter Function(double width) layoutFor;

  @override
  void paint(Canvas canvas, Size size) {
    if (selection.isCollapsed || text.isEmpty) return;
    final painter = layoutFor(size.width);
    final paint = Paint()..color = color;
    for (final box in painter.getBoxesForSelection(selection)) {
      canvas.drawRect(box.toRect(), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BlockSelectionPainter oldDelegate) {
    // 故意不比较 [layoutFor]：闭包没有有意义的相等性，且它的输入已被
    // text/style/textDirection/textScaler 覆盖，这些字段变了自然会重绘。
    return oldDelegate.text != text ||
        oldDelegate.style != style ||
        oldDelegate.selection != selection ||
        oldDelegate.color != color ||
        oldDelegate.textDirection != textDirection ||
        oldDelegate.textScaler != textScaler;
  }
}

/// 高亮背景:在文字下方绘制各高亮区间的半透明色块。与 [_BlockSelectionPainter]
/// 同模式(复用 state 缓存的 layout painter),但用 `getBoxesForRange`(不带
/// caret)且支持多个独立区间。
final class _BlockHighlightPainter extends CustomPainter {
  _BlockHighlightPainter({
    required this.text,
    required this.style,
    required this.highlights,
    required this.textDirection,
    required this.textScaler,
    required this.layoutFor,
  });

  final String text;
  final TextStyle? style;
  final List<TextAnnotation> highlights;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final TextPainter Function(double width) layoutFor;

  @override
  void paint(Canvas canvas, Size size) {
    if (highlights.isEmpty || text.isEmpty) return;
    final painter = layoutFor(size.width);
    for (final a in highlights) {
      final bg = a.background;
      if (bg == null) continue;
      final paint = Paint()..color = bg;
      // TextPainter 无 getBoxesForRange;用 getBoxesForSelection 传入 [start,end)
      // 区间(非 collapsed,无 caret 矩形),与 _BlockSelectionPainter 同源。
      final selection = TextSelection(baseOffset: a.start, extentOffset: a.end);
      for (final box in painter.getBoxesForSelection(selection)) {
        canvas.drawRect(box.toRect(), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BlockHighlightPainter oldDelegate) {
    // 故意不比较 layoutFor(闭包无有意义相等性,其输入已被 text/style/...覆盖)。
    // TextAnnotation 有值相等,listEquals 按值比较两轮标注列表。
    return oldDelegate.text != text ||
        oldDelegate.style != style ||
        oldDelegate.textDirection != textDirection ||
        oldDelegate.textScaler != textScaler ||
        !listEquals(oldDelegate.highlights, highlights);
  }
}
