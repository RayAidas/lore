import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_editor/lore_editor.dart';

EditorStyle _style() => const EditorStyle.defaults().copyWith(
  fontSize: 20,
  lineHeight: 1.6,
  letterSpacing: 0.3,
  contentWidth: 700,
  fontFamily: 'LXGWWenKai',
  fontFamilyFallback: ['Kaiti SC'],
);

void main() {
  test('bodyText 派生编辑器正文字号/行高/字距/字体', () {
    final style = _style();
    final body = EditorTypography.bodyText(style, ThemeData.light());
    expect(body, isNotNull);
    expect(body!.fontSize, 20);
    expect(body.height, 1.6);
    expect(body.letterSpacing, 0.3);
    expect(body.fontFamily, 'LXGWWenKai');
    expect(body.fontFamilyFallback, ['Kaiti SC']);
    // 颜色不在此覆写：继承自 bodyLarge（与编辑器块 textStyle 行为一致）。
    expect(body.color, ThemeData.light().textTheme.bodyLarge!.color);
  });

  test('titleText 派生标题字号（fontSize × titleScale）/字重/行高/字体，且非空', () {
    final style = _style();
    final title = EditorTypography.titleText(style, ThemeData.light());
    expect(title.fontSize, style.titleFontSize); // = fontSize * titleScale
    expect(title.fontSize, closeTo(20 * 1.3, 1e-9));
    expect(title.fontWeight, FontWeight.w700);
    expect(title.height, 1.2);
    expect(title.letterSpacing, 0.3);
    expect(title.fontFamily, 'LXGWWenKai');
    expect(title.fontFamilyFallback, ['Kaiti SC']);
    expect(title.color, ThemeData.light().colorScheme.onSurface);
  });

  test(
    'contentFrame = Align(topCenter) + ConstrainedBox(maxWidth: contentWidth)',
    () {
      final style = _style();
      final widget = EditorTypography.contentFrame(
        style,
        child: const SizedBox(),
      );
      expect(widget, isA<Align>());
      final align = widget as Align;
      expect(align.alignment, Alignment.topCenter);
      expect(align.child, isA<ConstrainedBox>());
      final box = align.child as ConstrainedBox;
      expect(box.constraints.maxWidth, 700);
      expect(box.child, isA<SizedBox>());
    },
  );

  test('readingInset / titleTopInset 与编辑器标题栏常量一致', () {
    expect(EditorTypography.readingInset, 52);
    expect(EditorTypography.titleTopInset, 42);
  });
}
