import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_editor/lore_editor.dart';

void main() {
  group('splitParagraphs', () {
    test('逐行切段，一行一段', () {
      expect(LoreReadingFlowPreview.splitParagraphs('第一段\n第二段\n第三段'), [
        '第一段',
        '第二段',
        '第三段',
      ]);
    });

    test('空行（连续换行）不计入段落', () {
      expect(LoreReadingFlowPreview.splitParagraphs('第一段\n\n第二段\n'), [
        '第一段',
        '第二段',
      ]);
    });

    test('规范化 CRLF / CR 换行', () {
      expect(LoreReadingFlowPreview.splitParagraphs('第一段\r\n第二段\r第三段'), [
        '第一段',
        '第二段',
        '第三段',
      ]);
    });

    test('纯空白文本返回空列表', () {
      expect(LoreReadingFlowPreview.splitParagraphs('\n\n  \t\n'), isEmpty);
    });
  });

  group('ensureIndent', () {
    const indent = '　　'; // 两个全角空格

    test('段首无缩进时补两个全角空格', () {
      expect(LoreReadingFlowPreview.ensureIndent('正文', indent), '　　正文');
    });

    test('已有全角缩进不再叠加', () {
      expect(LoreReadingFlowPreview.ensureIndent('　　正文', indent), '　　正文');
    });

    test('段首半角空格视为显式缩进，不叠加', () {
      expect(LoreReadingFlowPreview.ensureIndent(' 正文', indent), ' 正文');
    });

    test('indent 为空时原样返回', () {
      expect(LoreReadingFlowPreview.ensureIndent('正文', ''), '正文');
    });
  });

  testWidgets('渲染多段正文且每段补段首全角缩进', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: SizedBox(
            width: 300,
            child: LoreReadingFlowPreview(
              data: '第一段\n第二段',
              style: const EditorStyle.defaults(),
            ),
          ),
        ),
      ),
    );
    expect(find.text('　　第一段'), findsOneWidget);
    expect(find.text('　　第二段'), findsOneWidget);
  });

  testWidgets('firstLineIndent=false 时段首不补缩进', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: SizedBox(
            width: 300,
            child: LoreReadingFlowPreview(
              data: '第一段',
              style: const EditorStyle.defaults().copyWith(
                firstLineIndent: false,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('第一段'), findsOneWidget);
  });
}
