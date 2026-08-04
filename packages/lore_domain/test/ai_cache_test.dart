import 'package:lore_domain/lore_domain.dart';
import 'package:test/test.dart';

void main() {
  const entry = AiCacheEntry(
    timestampMillis: 1000,
    kind: AiCacheEntryKind.action,
    prompt: 'polish',
    contextSummary: '当前章节正文 · 100 字',
    output: '润色结果',
  );

  test('empty cache has no entries', () {
    expect(const AiCache.empty().entries, isEmpty);
  });

  test('append grows entries in order', () {
    final cache = const AiCache.empty()
        .append(entry)
        .append(
          const AiCacheEntry(
            timestampMillis: 2000,
            kind: AiCacheEntryKind.custom,
            prompt: '改成更口语',
            contextSummary: '选中文字 · 20 字',
            output: '结果',
          ),
        );

    expect(cache.entries, hasLength(2));
    expect(cache.entries[0].prompt, 'polish');
    expect(cache.entries[1].kind, AiCacheEntryKind.custom);
  });

  test('removeAt drops the entry at index', () {
    final cache = const AiCache.empty().append(entry).append(
      const AiCacheEntry(
        timestampMillis: 2000,
        kind: AiCacheEntryKind.custom,
        prompt: 'x',
        contextSummary: 'c',
        output: 'o',
      ),
    );

    final withoutFirst = cache.removeAt(0);
    expect(withoutFirst.entries, hasLength(1));
    expect(withoutFirst.entries.single.prompt, 'x');

    expect(cache.removeAt(99), same(cache), reason: '越界移除幂等');
  });

  test('clear empties the cache', () {
    final cache = const AiCache.empty().append(entry);
    expect(cache.clear().entries, isEmpty);
  });
}
