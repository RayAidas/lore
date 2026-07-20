import 'package:lore_domain/lore_domain.dart';
import 'package:test/test.dart';

void main() {
  group('TxtNovelParser', () {
    test('splits arabic-numbered chapters and drops leading matter', () {
      final parsed = TxtNovelParser.parse(
        text:
            '作者：佚名\n网址：x\n\n'
            '第1章 起点\n起点正文。\n第二段。\n\n'
            '第2章 远行\n远行正文。',
        fileName: '我的小说.txt',
      );
      expect(parsed.titleSuggestion, '我的小说');
      expect(parsed.chapters, hasLength(2));
      expect(parsed.chapters[0].subtitle, '起点');
      expect(parsed.chapters[0].body, '起点正文。\n第二段。');
      expect(parsed.chapters[1].subtitle, '远行');
      expect(parsed.chapters[1].body, '远行正文。');
    });

    test('recognizes chinese-numbered headings', () {
      final parsed = TxtNovelParser.parse(text: '第一章 龙城\n正文A\n第二章 飞将\n正文B');
      expect(parsed.chapters, hasLength(2));
      expect(parsed.chapters[0].subtitle, '龙城');
      expect(parsed.chapters[1].subtitle, '飞将');
    });

    test('recognizes 第N回/第N节 and Chapter N', () {
      final parsed = TxtNovelParser.parse(
        text: '第一回 桃园\nA\nChapter 2 Begins\nB',
      );
      expect(parsed.chapters, hasLength(2));
      expect(parsed.chapters[0].subtitle, '桃园');
      expect(parsed.chapters[1].subtitle, 'Begins');
    });

    test('recognizes role keywords as chapter boundaries', () {
      final parsed = TxtNovelParser.parse(
        text: '序章 楔子\n序言正文\n第1章 正篇\n正文\n后记 结语\n后记正文',
      );
      expect(parsed.chapters, hasLength(3));
      expect(parsed.chapters[0].subtitle, '楔子');
      expect(parsed.chapters[2].subtitle, '结语');
    });

    test('does not split on volume markers (第N卷 stays in body)', () {
      final parsed = TxtNovelParser.parse(text: '第1章 开端\n开端正文\n第一卷 风起\n风起正文');
      expect(parsed.chapters, hasLength(1));
      expect(parsed.chapters[0].subtitle, '开端');
      // 卷标记行作为正文保留在所属章节里。
      expect(parsed.chapters[0].body, contains('第一卷 风起'));
      expect(parsed.chapters[0].body, contains('风起正文'));
    });

    test('splits combined volume+chapter headings (第N卷 卷名 第M章 标题)', () {
      // 回归：莽荒纪等网文卷终章之后常出现「第六卷 破茧成蝶 第一章 水府四殿」
      // 这类卷+章合并行；旧正则因行首是「第N卷」（卷不在 [章节回]）而漏判，
      // 导致整卷被并入上一章（数十万字）。现在按其中的章节 token 切分，
      // 卷名不进入副标题。
      final parsed = TxtNovelParser.parse(
        text:
            '第二十六章 风雨欲来\n风雨正文\n'
            '第六卷 破茧成蝶 第一章 水府四殿\n水府正文\n'
            '第六卷 破茧成蝶 第二章 珍宝\n珍宝正文',
      );
      expect(parsed.chapters, hasLength(3));
      expect(parsed.chapters[0].subtitle, '风雨欲来');
      expect(parsed.chapters[1].subtitle, '水府四殿');
      expect(parsed.chapters[1].body, '水府正文');
      expect(parsed.chapters[2].subtitle, '珍宝');
    });

    test('splits combined heading without space before chapter token', () {
      // 变体：卷名紧接章节号，如「破茧成蝶第十七章 …」。
      final parsed = TxtNovelParser.parse(text: '第六卷 破茧成蝶第十七章 纪宁战童玉\n正文');
      expect(parsed.chapters, hasLength(1));
      expect(parsed.chapters[0].subtitle, '纪宁战童玉');
    });

    test('falls back to a single chapter when no heading is found', () {
      final parsed = TxtNovelParser.parse(text: '  整段没有标题的文字。  \n第二行。');
      expect(parsed.chapters, hasLength(1));
      expect(parsed.chapters[0].subtitle, isEmpty);
      expect(parsed.chapters[0].body, '整段没有标题的文字。\n第二行。');
    });

    test('skips headings but yields no chapters for whitespace-only text', () {
      final parsed = TxtNovelParser.parse(text: '   \n  \n');
      expect(parsed.chapters, isEmpty);
    });

    test('tolerates leading whitespace before headings', () {
      final parsed = TxtNovelParser.parse(
        text: '   第1章 缩进标题\n正文\n\t第2章 制表符\n正文2',
      );
      expect(parsed.chapters, hasLength(2));
      expect(parsed.chapters[0].subtitle, '缩进标题');
      expect(parsed.chapters[1].subtitle, '制表符');
    });

    test('strips separators between heading label and subtitle', () {
      final parsed = TxtNovelParser.parse(
        text: '第1章：带冒号的标题\n正文\n第2章 - 带破折号\n正文2',
      );
      expect(parsed.chapters[0].subtitle, '带冒号的标题');
      expect(parsed.chapters[1].subtitle, '带破折号');
    });

    test('normalizes CRLF and CR line endings before splitting', () {
      final parsed = TxtNovelParser.parse(text: '第1章 A\r\n正文A\r第2章 B\n正文B');
      expect(parsed.chapters, hasLength(2));
      expect(parsed.chapters[0].body, '正文A');
      expect(parsed.chapters[1].body, '正文B');
    });

    test('sanitizes file name into title suggestion', () {
      final parsed = TxtNovelParser.parse(
        text: '第1章\nx',
        fileName: '/a/b/书*名?.txt',
      );
      expect(parsed.titleSuggestion, '书名');
    });
  });
}
