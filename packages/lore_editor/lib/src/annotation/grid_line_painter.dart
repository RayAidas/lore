import 'package:flutter/material.dart';
import 'package:lore_domain/lore_domain.dart';

/// 段落网格线 painter：在每行文字底部画一条横线（实线 / 虚线）。
///
/// 编辑器块（`LoreLargeTextEditor`）与历史 diff 段落共用——两者都是「一段文本 +
/// 已 layout 的 TextPainter」，借此 painter 在每行底部画线，使网格线与文字行底
/// 对齐。[drawTopLine] 为真时在顶部 y=0 补一条（编辑器用来画上一段空行底部、即
/// 本段上方的网格线；diff 段落一般不画）。
///
/// paint 不自己 layout，而是通过 [layoutFor] 借用调用方已 layout 的 painter 取行高
/// （编辑器复用 state 缓存；diff 临时构造），保证与字形层同源、行底对齐。
final class TextGridLinePainter extends CustomPainter {
  TextGridLinePainter({
    required this.mode,
    required this.color,
    required this.drawTopLine,
    required this.text,
    required this.style,
    required this.textDirection,
    required this.textScaler,
    required this.layoutFor,
  });

  final GridLineMode mode;
  final Color color;
  final bool drawTopLine;
  final String text;
  // style/textDirection/textScaler 仅用于 shouldRepaint 比较——paint 不自己
  // layout，而是通过 [layoutFor] 借用调用方已 layout 的 painter。
  final TextStyle? style;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final TextPainter Function(double width) layoutFor;

  @override
  void paint(Canvas canvas, Size size) {
    if (mode == GridLineMode.none || size.isEmpty) return;
    final painter = layoutFor(size.width);
    final lineHeight = painter.preferredLineHeight;
    if (lineHeight <= 0) return;
    // block 实际高度除以行高 → 视觉行数（TextField minLines:1 保证至少 1）。
    // 上限 10000 远超单 block 现实行数——长段在 controller 层已按
    // [ChunkedTextBuffer.targetChunkLength] 拆成多 block，此处仅防 lineHeight
    // 趋近 0 的病态值把行数放大。
    final rows = (size.height / lineHeight).round().clamp(1, 10000);
    const strokeWidth = 0.6;
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    // 收集所有横线的 y：顶部线（偏移半个线宽，避免描边上半被 canvas 顶部裁掉
    // 而比行底线细一半）+ 每行底部（末行贴 block 底吸收 sub-pixel）。
    final ys = <double>[
      if (drawTopLine) strokeWidth / 2,
      for (var i = 1; i <= rows; i += 1)
        i == rows ? size.height : i * lineHeight,
    ];

    // 所有线段并入单个 [Path]、一次 [Canvas.drawPath] 提交。dashed 下尤其关键：
    // 原先每行 × 每 dash 一次 [Canvas.drawLine]（900px × 20 行 ≈ 2.4k 次/块/帧），
    // 合并后每 block 仅一次 draw 调用。
    final path = Path();
    if (mode == GridLineMode.dashed) {
      const dash = 4.0;
      const step = dash + 4.0; // dash + gap
      for (final y in ys) {
        for (var x = 0.0; x < size.width; x += step) {
          final end = x + dash < size.width ? x + dash : size.width;
          path.moveTo(x, y);
          path.lineTo(end, y);
        }
      }
    } else {
      for (final y in ys) {
        path.moveTo(0, y);
        path.lineTo(size.width, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant TextGridLinePainter oldDelegate) {
    // 故意不比较 [layoutFor]：闭包无有意义的相等性，其输入已被
    // text/style/textDirection/textScaler 覆盖，这些字段变自然重绘。
    // 另未比较画布宽度：contentWidth 调整或窗口缩放改变 width 时，
    // [RenderCustomPaint] 会因 size 变化触发重绘，故无需在此显式比较。
    return oldDelegate.mode != mode ||
        oldDelegate.color != color ||
        oldDelegate.drawTopLine != drawTopLine ||
        oldDelegate.text != text ||
        oldDelegate.style != style ||
        oldDelegate.textDirection != textDirection ||
        oldDelegate.textScaler != textScaler;
  }
}
