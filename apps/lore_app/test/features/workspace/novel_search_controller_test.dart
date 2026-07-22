import 'package:flutter_test/flutter_test.dart';
import 'package:lore_app/features/workspace/novel_search_controller.dart';
import 'package:lore_editor/lore_editor.dart';

void main() {
  group('matchChapters', () {
    test('各章节匹配独立，offset 相对各自正文', () {
      final bodies = ['主角登场，主角说话。', '配角提及主角一次。'];
      final query = SearchQuery(
        pattern: '主角',
        caseSensitive: false,
        useRegex: false,
      );
      final result = matchChapters(bodies, query);

      expect(result.length, 2);
      expect(result[0].length, 2);
      expect(result[0][0].bodyOffset, 0);
      expect(result[0][1].bodyOffset, '主角登场，'.length); // 第二处「主角」
      expect(result[1].length, 1);
      expect(result[1][0].bodyOffset, '配角提及'.length);
    });

    test('snippet 的高亮区间精确覆盖匹配文本', () {
      final prefix = '前文'.padRight(30, 'x'); // 30 字符
      const keyword = '关键词';
      final suffix = '后文'.padRight(30, 'x');
      final body = '$prefix$keyword$suffix';
      final query = SearchQuery(
        pattern: '关键词',
        caseSensitive: false,
        useRegex: false,
      );
      final match = matchChapters([body], query).single.single;

      expect(match.bodyOffset, prefix.length);
      expect(match.length, '关键词'.length);
      expect(
        match.snippet.substring(match.snippetMatchStart, match.snippetMatchEnd),
        '关键词',
      );
    });

    test('匹配靠前时片段无前省略号', () {
      final result = matchChapters([
        '关键词尾随内容内容内容',
      ], SearchQuery(pattern: '关键词', caseSensitive: false, useRegex: false));
      final match = result.single.single;
      expect(match.snippetMatchStart, lessThan('关键词'.length));
    });

    test('空 pattern 不产生匹配', () {
      final result = matchChapters([
        '任意正文',
      ], SearchQuery(pattern: '', caseSensitive: false, useRegex: false));
      expect(result.single, isEmpty);
    });

    test('片段内换行转为空格、offset 仍相对正文', () {
      final result = matchChapters([
        '关键词\n下一行',
      ], SearchQuery(pattern: '关键词', caseSensitive: false, useRegex: false));
      final match = result.single.single;
      expect(match.bodyOffset, 0);
      expect(match.snippet, contains(' '));
      expect(match.snippet, isNot(contains('\n')));
    });

    test('正则模式匹配多个结果', () {
      final result = matchChapters([
        '电话 13800000000 与 13900000000',
      ], SearchQuery(pattern: r'1\d+', caseSensitive: false, useRegex: true));
      expect(result.single.length, 2);
      expect(result.single[0].length, 11);
      expect(result.single[1].length, 11);
    });
  });
}
