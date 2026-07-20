import 'package:lore_domain/lore_domain.dart';
import 'package:test/test.dart';

void main() {
  group('characterCountOf', () {
    test('counts non-whitespace runes when first line is not a title', () {
      expect(characterCountOf('hello world'), 10);
      expect(characterCountOf('你好世界'), 4);
    });

    test('strips TXT title line, counts body only', () {
      expect(characterCountOf('第1章\n正文内容'), 4); // 正文内容
      expect(characterCountOf('第3章 甜蜜的家\n家是温暖的'), 5); // 家是温暖的
    });

    test('strips Markdown title line, counts body only', () {
      expect(characterCountOf('# 第1章\n正文内容'), 4); // 正文内容
      expect(characterCountOf('# 第1章 副标题\n正文内容'), 4); // 正文内容
    });

    test('title-only document is zero', () {
      expect(characterCountOf('第1章'), 0);
      expect(characterCountOf('第1章\n'), 0);
      expect(characterCountOf('# 第1章\n'), 0);
      expect(characterCountOf('# 第1章 副标题'), 0);
    });

    test('empty or whitespace-only string is zero', () {
      expect(characterCountOf(''), 0);
      expect(characterCountOf('   \n\t  '), 0);
    });

    test('ignores whitespace inside body', () {
      expect(characterCountOf('第1章\n  正  文  '), 2); // 正文
    });

    test('counts body across multiple lines, strips only the title line', () {
      expect(characterCountOf('第1章\n第一段\n第二段'), 6); // 第一段第二段
    });

    test('handles CRLF line endings', () {
      expect(characterCountOf('第3章\r\n正文\r\n'), 2); // 正文
    });

    test('handles classic Mac CR-only line endings', () {
      expect(characterCountOf('第3章\r正文'), 2); // 正文
    });

    test('hash without space is not a Markdown title, counts full text', () {
      // `#第1章` 不符合 Markdown H1（# 后须空白）→ 按非标题全文计数，# 计入。
      expect(characterCountOf('#第1章\n正文'), 6); // #第1章正文
    });
  });
}
