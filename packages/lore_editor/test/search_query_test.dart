import 'package:lore_editor/src/find_replace/search_query.dart';
import 'package:test/test.dart';

void main() {
  group('SearchQuery.findAllIn', () {
    test('returns empty for empty pattern', () {
      const query = SearchQuery(
        pattern: '',
        caseSensitive: false,
        useRegex: false,
      );
      expect(query.findAllIn('hello'), isEmpty);
    });

    test('locates plain substring occurrences', () {
      const query = SearchQuery(
        pattern: 'ab',
        caseSensitive: false,
        useRegex: false,
      );
      final matches = query.findAllIn('ab x ab y ab');
      expect(matches.map((m) => (m.start, m.end)).toList(), [
        (0, 2),
        (5, 7),
        (10, 12),
      ]);
    });

    test('honors caseSensitive flag', () {
      const sensitive = SearchQuery(
        pattern: 'Ab',
        caseSensitive: true,
        useRegex: false,
      );
      const insensitive = SearchQuery(
        pattern: 'Ab',
        caseSensitive: false,
        useRegex: false,
      );
      final sensitiveMatches = sensitive.findAllIn('aB Ab ab');
      expect(sensitiveMatches.length, 1);
      expect(sensitiveMatches.single.start, 3);
      expect(insensitive.findAllIn('aB Ab ab').length, 3);
    });

    test('supports regex matches', () {
      const query = SearchQuery(
        pattern: r'\d+',
        caseSensitive: false,
        useRegex: true,
      );
      final matches = query.findAllIn('a 12 b 345');
      expect(matches.length, 2);
      expect((matches[0].start, matches[0].end), (2, 4));
      expect((matches[1].start, matches[1].end), (7, 10));
    });

    test('returns empty on invalid regex', () {
      const query = SearchQuery(
        pattern: '(',
        caseSensitive: false,
        useRegex: true,
      );
      expect(query.findAllIn('text'), isEmpty);
    });
  });
}
