import 'package:lore_domain/lore_domain.dart';
import 'package:test/test.dart';

void main() {
  test('empty has no links', () {
    const links = NovelOutlineLinks.empty();
    expect(links.forNovel('novel-a'), isEmpty);
  });

  test('forNovel returns the linked paths of that novel only', () {
    const links = NovelOutlineLinks({
      'novel-a': ['小说A/大纲/大纲.md'],
      'novel-b': ['小说B/大纲/大纲.md', '小说B/大纲/大纲2.md'],
    });
    expect(links.forNovel('novel-a'), ['小说A/大纲/大纲.md']);
    expect(links.forNovel('novel-b'), hasLength(2));
    expect(links.forNovel('unknown'), isEmpty);
  });

  test('withLink appends and is idempotent on duplicates', () {
    final links = NovelOutlineLinks.empty()
        .withLink('novel-a', '小说A/大纲/大纲.md')
        .withLink('novel-a', '小说A/大纲/大纲.md');

    expect(links.forNovel('novel-a'), ['小说A/大纲/大纲.md']);
  });

  test('withLink keeps existing links of other novels', () {
    final links = NovelOutlineLinks.empty()
        .withLink('novel-a', '小说A/大纲/大纲.md')
        .withLink('novel-b', '小说B/大纲/大纲.md');

    expect(links.forNovel('novel-a'), ['小说A/大纲/大纲.md']);
    expect(links.forNovel('novel-b'), ['小说B/大纲/大纲.md']);
  });

  test('withoutLink removes one path and drops empty keys', () {
    final links = const NovelOutlineLinks({
      'novel-a': ['A.md', 'A2.md'],
      'novel-b': ['B.md'],
    });

    final oneRemoved = links.withoutLink('novel-a', 'A.md');
    expect(oneRemoved.forNovel('novel-a'), ['A2.md']);
    expect(oneRemoved.forNovel('novel-b'), ['B.md']);

    final lastRemoved = oneRemoved.withoutLink('novel-b', 'B.md');
    expect(lastRemoved.forNovel('novel-b'), isEmpty);
    expect(lastRemoved.pathsByNovelId.containsKey('novel-b'), isFalse);
  });

  test('withoutLink is idempotent when path is absent', () {
    const links = NovelOutlineLinks({'novel-a': ['A.md']});
    expect(links.withoutLink('novel-a', 'missing.md'), same(links));
  });
}
