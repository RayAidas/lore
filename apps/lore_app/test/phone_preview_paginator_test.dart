import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_app/features/workspace/phone_preview/phone_preview_paginator.dart';

const _style = TextStyle(fontSize: 14, height: 1.4);
const _indent = '　　';

/// 重测一页的渲染高度：sum(各段文本高度) + 段间距（页内非首段且为新段落起始）。
double _remeasurePageHeight(
  PhonePreviewPage page,
  double boxWidth,
  double gap,
  TextPainter painter,
) {
  var h = 0.0;
  for (var j = 0; j < page.segments.length; j++) {
    final seg = page.segments[j];
    painter.text = TextSpan(text: seg.text, style: _style);
    painter.layout(maxWidth: boxWidth);
    h += painter.height;
    if (j > 0 && seg.newParagraph) h += gap;
  }
  return h;
}

void main() {
  testWidgets('短文本一页放下，文本不丢失', (tester) async {
    final paginator = PhonePreviewPaginator(
      boxWidth: 300,
      pageHeight: 400,
      firstPageHeight: 400,
      style: _style,
      paragraphGap: 10,
      paragraphIndent: _indent,
    );
    final pages = paginator.paginate(['第一段内容', '第二段内容']);
    expect(pages.length, 1);
    expect(
      pages.first.segments.map((s) => s.text).join(),
      '$_indent第一段内容$_indent第二段内容',
    );
  });

  testWidgets('空输入返回空页列表', (tester) async {
    final paginator = PhonePreviewPaginator(
      boxWidth: 300,
      pageHeight: 400,
      firstPageHeight: 400,
      style: _style,
      paragraphGap: 10,
    );
    expect(paginator.paginate([]), isEmpty);
    expect(paginator.paginate(['', '  ', '\n']), isEmpty);
  });

  testWidgets('长文本切成多页，每页重测不超过页高、无空页、文本完整', (tester) async {
    const boxWidth = 280.0;
    const gap = 8.0;
    const pageH = 300.0;
    final paragraphs = List.generate(
      60,
      (i) => '这是第$i段，写长一点的内容来强制换行和分页，多写一些字。' * 3,
    );
    final paginator = PhonePreviewPaginator(
      boxWidth: boxWidth,
      pageHeight: pageH,
      firstPageHeight: pageH,
      style: _style,
      paragraphGap: gap,
      paragraphIndent: _indent,
    );
    final pages = paginator.paginate(paragraphs);
    expect(pages.length, greaterThan(1));

    final painter = TextPainter(textDirection: TextDirection.ltr);
    addTearDown(painter.dispose);

    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      // 无空页。
      expect(
        page.segments.any((s) => s.text.isNotEmpty),
        true,
        reason: 'page $i',
      );
      // 重测高度不超页高（留亚像素容差）。
      final h = _remeasurePageHeight(page, boxWidth, gap, painter);
      expect(h, lessThanOrEqualTo(pageH + 1.0), reason: 'page $i height=$h');
    }

    // 文本完整：所有段拼接 == 所有（带缩进的）段落拼接，顺序不变。
    final rejoined = pages.expand((p) => p.segments).map((s) => s.text).join();
    final expected = paragraphs.map((p) => '$_indent$p').join();
    expect(rejoined, expected);
  });

  testWidgets('第 1 页扣除标题高度（firstPageHeight < pageHeight），首页内容更少', (
    tester,
  ) async {
    const boxWidth = 280.0;
    const gap = 8.0;
    final paragraphs = List.generate(
      80,
      (i) => '第$i段内容写长一点来填满多页，继续写更多字以触发分页。' * 3,
    );
    final paginator = PhonePreviewPaginator(
      boxWidth: boxWidth,
      pageHeight: 300,
      firstPageHeight: 150, // 首页只给 150，扣除标题区
      style: _style,
      paragraphGap: gap,
      paragraphIndent: _indent,
    );
    final pages = paginator.paginate(paragraphs);
    expect(pages.length, greaterThan(1));

    final painter = TextPainter(textDirection: TextDirection.ltr);
    addTearDown(painter.dispose);

    final firstH = _remeasurePageHeight(pages.first, boxWidth, gap, painter);
    expect(firstH, lessThanOrEqualTo(150 + 1.0));
    // 后续页用满 300。
    final secondH = _remeasurePageHeight(pages[1], boxWidth, gap, painter);
    expect(secondH, greaterThan(firstH));
  });

  testWidgets('续接片段标为非新段落（newParagraph=false）且不含段首缩进', (tester) async {
    // 单段超长：必然跨页，第 2 页首段是续接。
    final superLong = List.filled(1, '字' * 5000);
    final paginator = PhonePreviewPaginator(
      boxWidth: 200,
      pageHeight: 120,
      firstPageHeight: 120,
      style: _style,
      paragraphGap: 8,
      paragraphIndent: _indent,
    );
    final pages = paginator.paginate(superLong);
    expect(pages.length, greaterThan(1));
    final secondFirst = pages[1].segments.first;
    expect(secondFirst.newParagraph, isFalse);
    // 续接是段中子串，不应以缩进开头。
    expect(secondFirst.text.startsWith(_indent), isFalse);
  });

  testWidgets('页面比一行还矮时强制放首行：不无限循环、每段非空', (tester) async {
    final paginator = PhonePreviewPaginator(
      boxWidth: 300,
      pageHeight: 5, // 比一行（≈20px）还矮，必然走「强制放首行」分支
      firstPageHeight: 5,
      style: _style,
      paragraphGap: 0,
      paragraphIndent: _indent,
    );
    final pages = paginator.paginate(['一段会被强制分行的较长正文内容多写几个字']);
    expect(pages, isNotEmpty);
    expect(
      pages.every((p) => p.segments.every((s) => s.text.isNotEmpty)),
      true,
    );
  });

  testWidgets('已带缩进的段落不重复加缩进（与 ensureIndent 一致）', (tester) async {
    final paginator = PhonePreviewPaginator(
      boxWidth: 300,
      pageHeight: 400,
      firstPageHeight: 400,
      style: _style,
      paragraphGap: 10,
      paragraphIndent: _indent,
    );
    final pages = paginator.paginate(['$_indent已有缩进的段落']);
    expect(pages.first.segments.first.text, '$_indent已有缩进的段落');
  });
}
