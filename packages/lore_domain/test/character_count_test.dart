import 'package:lore_domain/lore_domain.dart';
import 'package:test/test.dart';

void main() {
  group('characterCountOf', () {
    test('counts non-whitespace runes', () {
      expect(characterCountOf('hello world'), 10);
      expect(characterCountOf('你好世界'), 4);
    });

    test('ignores leading/trailing/internal whitespace', () {
      expect(characterCountOf('  第1章\n正文  '), 5); // 第1章正文
    });

    test('empty or whitespace-only string is zero', () {
      expect(characterCountOf(''), 0);
      expect(characterCountOf('   \n\t  '), 0);
    });

    test('counts markdown seed title line', () {
      expect(characterCountOf('# 第1章\n'), 4); // # 第1章 -> #第1章
    });
  });
}
