import 'package:flutter/material.dart';

/// 文本上的只读渲染标注：背景色 / 字形色 / 删除线。
///
/// 是 highlight（仅 [background]）与 diff（[background] + [color] + [strikethrough]）
/// 共用的统一模型——把「在某段文本区间上叠什么视觉」抽象成一种数据，由各宿主
/// （编辑器背景 painter / 只读 `SelectableText` 的 span 树）按自身机制渲染。
/// 这样 highlight 与 diff 共用同一套标注语义，新增只读标注表面（搜索高亮、批注
/// 等）也直接复用。
///
/// range 为所在文本块的【局部】字符 offset，半开区间 `[start, end)`，与编辑器块
/// 内坐标系一致（见 `LoreLargeTextEditor._localHighlightsForBlock` 的全局→局部换算）。
final class TextAnnotation {
  const TextAnnotation({
    required this.start,
    required this.end,
    this.background,
    this.color,
    this.strikethrough = false,
  });

  /// 区间起点（含），块内局部 offset。
  final int start;

  /// 区间终点（不含），块内局部 offset。
  final int end;

  /// 背景色（高亮底色 / diff 增删底色）。null 表示不画背景。
  final Color? background;

  /// 字形色（diff 增删字色）。null 表示继承宿主正文色。
  final Color? color;

  /// 是否给区间内字形加删除线（diff 删除）。
  final bool strikethrough;

  /// 值相等：编辑器 highlight painter 的 `shouldRepaint` 用 `listEquals` 比较两轮
  /// 标注列表，依赖元素值相等以避免每帧无谓重绘。
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextAnnotation &&
          start == other.start &&
          end == other.end &&
          background == other.background &&
          color == other.color &&
          strikethrough == other.strikethrough;

  @override
  int get hashCode => Object.hash(start, end, background, color, strikethrough);
}
