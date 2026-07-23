import 'package:flutter_test/flutter_test.dart';
import 'package:lore_app/features/workspace/quick_open/quick_open_matcher.dart';

void main() {
  group('fuzzyMatch', () {
    test('空 query 返回 null', () {
      expect(fuzzyMatch('', 'abc'), isNull);
    });

    test('非子序列返回 null', () {
      expect(fuzzyMatch('xyz', 'abc'), isNull);
      expect(fuzzyMatch('ba', 'abc'), isNull); // 顺序不符
    });

    test('完全匹配命中所有下标', () {
      final m = fuzzyMatch('abc', 'abc');
      expect(m, isNotNull);
      expect(m!.matchedIndices, [0, 1, 2]);
    });

    test('大小写不敏感', () {
      final m = fuzzyMatch('ABC', 'abc');
      expect(m, isNotNull);
      expect(m!.matchedIndices, [0, 1, 2]);
    });

    test('子序列下标按序返回', () {
      final m = fuzzyMatch('ac', 'abc');
      expect(m, isNotNull);
      expect(m!.matchedIndices, [0, 2]);
    });

    test('前缀匹配得分高于后段匹配', () {
      final prefix = fuzzyMatch('ab', 'abcd')!;
      final later = fuzzyMatch('cd', 'abcd')!;
      expect(prefix.score, greaterThan(later.score));
    });

    test('词首与连续匹配加分(串首 + 跟随分隔符)', () {
      // 'fz' 在 'fast_zoom':f 串首, z 跟在 '_' 后(词首)。
      final m = fuzzyMatch('fz', 'fast_zoom')!;
      expect(m.matchedIndices, [0, 5]);
      expect(m.score, greaterThan(0));
    });

    test('中文按字符匹配', () {
      final m = fuzzyMatch('风起', '第二章 风起云涌');
      expect(m, isNotNull);
      expect(m!.matchedIndices, [4, 5]);
    });
  });
}
