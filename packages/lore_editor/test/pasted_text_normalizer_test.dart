import 'package:flutter_test/flutter_test.dart';
import 'package:lore_editor/src/large_text/pasted_text_normalizer.dart';

void main() {
  const indent = '　　'; // U+3000 × 2，与本编辑器段首缩进一致

  group('normalizePastedText', () {
    test('collapses blank-line paragraph separators into single newline', () {
      expect(normalizePastedText('第一段\n\n第二段'), '第一段\n第二段');
    });

    test('collapses three or more consecutive newlines into one', () {
      expect(normalizePastedText('第一段\n\n\n第二段'), '第一段\n第二段');
    });

    test('preserves a single newline (intra-paragraph line break)', () {
      expect(normalizePastedText('第一行\n第二行'), '第一行\n第二行');
    });

    test('normalizes CRLF paragraph separators from other apps', () {
      expect(normalizePastedText('第一段\r\n\r\n第二段'), '第一段\n第二段');
    });

    test('normalizes lone CR to LF', () {
      expect(normalizePastedText('第一段\r第二段'), '第一段\n第二段');
    });

    test('handles multiple blank lines across many paragraphs', () {
      const source = '甲\n\n乙\n\n\n丙\n丁\n\n戊';
      expect(normalizePastedText(source), '甲\n乙\n丙\n丁\n戊');
    });

    test('returns input unchanged when already normalized', () {
      expect(normalizePastedText('甲\n乙\n丙'), '甲\n乙\n丙');
    });
  });

  group('indentPastedParagraphs', () {
    test('indents every paragraph after a newline', () {
      expect(
        indentPastedParagraphs('甲\n乙\n丙', indent),
        '甲\n$indent乙\n$indent丙',
      );
    });

    test('leaves the first paragraph untouched by default', () {
      expect(indentPastedParagraphs('甲\n乙', indent), '甲\n$indent乙');
    });

    test('indents the first paragraph when indentAtStart is true', () {
      expect(
        indentPastedParagraphs('甲\n乙', indent, indentAtStart: true),
        '$indent甲\n$indent乙',
      );
    });

    test('does not double-indent an already-indented first paragraph', () {
      expect(
        indentPastedParagraphs('$indent甲\n乙', indent, indentAtStart: true),
        '$indent甲\n$indent乙',
      );
    });

    test('indents a single paragraph when indentAtStart is true', () {
      expect(
        indentPastedParagraphs('单段', indent, indentAtStart: true),
        '$indent单段',
      );
    });

    test('indents a trailing newline (opens a new empty paragraph)', () {
      expect(indentPastedParagraphs('甲\n', indent), '甲\n$indent');
    });

    test('returns empty input unchanged even with indentAtStart', () {
      expect(indentPastedParagraphs('', indent, indentAtStart: true), '');
    });

    test('returns input unchanged when indent is empty', () {
      expect(indentPastedParagraphs('甲\n乙', ''), '甲\n乙');
    });

    test('returns input unchanged when there is no newline', () {
      expect(indentPastedParagraphs('单段无换行', indent), '单段无换行');
    });

    test('is a no-op on already fully-indented text', () {
      final text = '$indent甲\n$indent乙';
      expect(indentPastedParagraphs(text, indent, indentAtStart: true), text);
    });
  });

  group('pasteInsertsAtParagraphStart', () {
    test('true at document start', () {
      expect(pasteInsertsAtParagraphStart('甲\n乙', 0), isTrue);
    });

    test('true when previous char is a newline', () {
      expect(pasteInsertsAtParagraphStart('甲\n乙', 2), isTrue);
    });

    test('false mid-paragraph', () {
      expect(pasteInsertsAtParagraphStart('甲乙\n丙', 1), isFalse);
    });

    test('false at end of doc when last char is not a newline', () {
      expect(pasteInsertsAtParagraphStart('甲乙', 2), isFalse);
    });

    test('true at end of doc when last char is a newline', () {
      expect(pasteInsertsAtParagraphStart('甲\n', 2), isTrue);
    });

    test('clamps negative offset (invalid selection) to paragraph start', () {
      expect(pasteInsertsAtParagraphStart('甲乙', -1), isTrue);
    });

    test('clamps offset beyond length to end of doc', () {
      expect(pasteInsertsAtParagraphStart('甲乙', 99), isFalse);
      expect(pasteInsertsAtParagraphStart('甲\n', 99), isTrue);
    });

    test('true for empty document', () {
      expect(pasteInsertsAtParagraphStart('', 0), isTrue);
    });
  });

  group('normalize then indent (paste pipeline)', () {
    test('mid-paragraph paste: first paragraph stays unindented', () {
      const external = '第一段\n\n第二段\n\n第三段';
      expect(
        indentPastedParagraphs(normalizePastedText(external), indent),
        '第一段\n$indent第二段\n$indent第三段',
      );
    });

    test('paragraph-start paste: first paragraph is also indented', () {
      const external = '第一段\n\n第二段';
      expect(
        indentPastedParagraphs(
          normalizePastedText(external),
          indent,
          indentAtStart: true,
        ),
        '$indent第一段\n$indent第二段',
      );
    });
  });
}
