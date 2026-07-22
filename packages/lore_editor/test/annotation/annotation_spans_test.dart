import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_editor/lore_editor.dart';

TextSpan _span(InlineSpan s) => s as TextSpan;

void main() {
  test('空文本返回空列表', () {
    expect(buildAnnotationSpans('', const []), isEmpty);
  });

  test('无标注返回整段无样式 span', () {
    final spans = buildAnnotationSpans('雨夜', const []);
    expect(spans, hasLength(1));
    expect(_span(spans.first).text, '雨夜');
    expect(_span(spans.first).style, isNull);
  });

  test('无视觉/零长度标注被忽略，等同于无标注', () {
    final spans = buildAnnotationSpans('雨夜', [
      const TextAnnotation(start: 0, end: 1), // 无 bg/color/strikethrough
      const TextAnnotation(
        start: 0,
        end: 0,
        background: Color(0xFF000000),
      ), // 零长度
    ]);
    expect(spans, hasLength(1));
    expect(_span(spans.first).text, '雨夜');
  });

  test('单标注：前导无样式 + 区间套 background/color', () {
    final spans = buildAnnotationSpans('0123456789', [
      const TextAnnotation(
        start: 2,
        end: 5,
        background: Color(0x11FF0000),
        color: Color(0xFF00FF00),
      ),
    ]);
    expect(spans, hasLength(3));
    expect(_span(spans[0]).text, '01');
    expect(_span(spans[0]).style, isNull);
    expect(_span(spans[1]).text, '234');
    expect(_span(spans[1]).style?.backgroundColor, const Color(0x11FF0000));
    expect(_span(spans[1]).style?.color, const Color(0xFF00FF00));
    expect(_span(spans[2]).text, '56789');
    expect(_span(spans[2]).style, isNull);
  });

  test('标注覆盖整段：单个带样式 span', () {
    final spans = buildAnnotationSpans('abc', [
      const TextAnnotation(start: 0, end: 3, background: Color(0xFF000000)),
    ]);
    expect(spans, hasLength(1));
    expect(_span(spans.first).text, 'abc');
    expect(_span(spans.first).style?.backgroundColor, const Color(0xFF000000));
  });

  test('相邻标注之间不插入空段（末尾未标注段保留）', () {
    final spans = buildAnnotationSpans('abcdef', [
      const TextAnnotation(start: 0, end: 2, color: Color(0xFF111111)),
      const TextAnnotation(start: 2, end: 4, color: Color(0xFF222222)),
    ]);
    // ab(色1) + cd(色2) + ef(无样式尾段)。
    expect(spans, hasLength(3));
    expect(_span(spans[0]).text, 'ab');
    expect(_span(spans[0]).style?.color, const Color(0xFF111111));
    expect(_span(spans[1]).text, 'cd');
    expect(_span(spans[1]).style?.color, const Color(0xFF222222));
    expect(_span(spans[2]).text, 'ef');
    expect(_span(spans[2]).style, isNull);
  });

  test('删除线：decoration = lineThrough，decorationColor = color', () {
    final spans = buildAnnotationSpans('abc', [
      const TextAnnotation(
        start: 0,
        end: 3,
        color: Color(0xFFC2364B),
        strikethrough: true,
      ),
    ]);
    final style = _span(spans.first).style;
    expect(style?.decoration, TextDecoration.lineThrough);
    expect(style?.decorationColor, const Color(0xFFC2364B));
  });

  test('越界标注被 clamp 到文本范围', () {
    final spans = buildAnnotationSpans('ab', [
      const TextAnnotation(start: -3, end: 10, background: Color(0xFF000000)),
    ]);
    expect(spans, hasLength(1));
    expect(_span(spans.first).text, 'ab');
    expect(_span(spans.first).style?.backgroundColor, const Color(0xFF000000));
  });

  test('重叠标注：后者截掉与前者重叠的头部', () {
    // [0,4) 与 [2,5) 重叠 → 第一段 0..4 着色，第二段截为 4..5。
    final spans = buildAnnotationSpans('012345', [
      const TextAnnotation(start: 0, end: 4, color: Color(0xFFAAAAAA)),
      const TextAnnotation(start: 2, end: 5, color: Color(0xFFBBBBBB)),
    ]);
    expect(spans, hasLength(3));
    expect(_span(spans[0]).text, '0123');
    expect(_span(spans[0]).style?.color, const Color(0xFFAAAAAA));
    expect(_span(spans[1]).text, '4');
    expect(_span(spans[1]).style?.color, const Color(0xFFBBBBBB));
    expect(_span(spans[2]).text, '5');
    expect(_span(spans[2]).style, isNull);
  });

  test('无序传入的标注按起点排序后切分', () {
    final spans = buildAnnotationSpans('0123456789', [
      const TextAnnotation(start: 7, end: 9, color: Color(0xFFBBBBBB)),
      const TextAnnotation(start: 1, end: 3, color: Color(0xFFAAAAAA)),
    ]);
    expect(_span(spans[0]).text, '0');
    expect(_span(spans[1]).text, '12');
    expect(_span(spans[1]).style?.color, const Color(0xFFAAAAAA));
    expect(_span(spans[2]).text, '3456');
    expect(_span(spans[3]).text, '78');
    expect(_span(spans[3]).style?.color, const Color(0xFFBBBBBB));
    expect(_span(spans[4]).text, '9');
  });
}
