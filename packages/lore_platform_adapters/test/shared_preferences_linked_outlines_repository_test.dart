import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_platform_adapters/lore_platform_adapters.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferencesLinkedOutlinesRepository repository;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repository = const SharedPreferencesLinkedOutlinesRepository();
  });

  test('returns null when nothing stored', () async {
    expect(await repository.load(), isNull);
  });

  test('round-trips links through save and load', () async {
    final links = const NovelOutlineLinks({
      'novel-a': ['小说A/大纲/大纲.md', '小说A/大纲/大纲2.md'],
      'novel-b': ['小说B/大纲/大纲.md'],
    });

    await repository.save(links);

    final loaded = await repository.load();
    expect(loaded, isNotNull);
    expect(loaded!.forNovel('novel-a'), ['小说A/大纲/大纲.md', '小说A/大纲/大纲2.md']);
    expect(loaded.forNovel('novel-b'), ['小说B/大纲/大纲.md']);
    expect(loaded.forNovel('unknown'), isEmpty);
  });

  test('returns null for a corrupted blob', () async {
    SharedPreferences.setMockInitialValues({
      'lore.agent.linked_outlines': 'not-json',
    });
    expect(await repository.load(), isNull);
  });

  test('returns null for a wrong schema version', () async {
    SharedPreferences.setMockInitialValues({
      'lore.agent.linked_outlines': jsonEncode({'schemaVersion': 99}),
    });
    expect(await repository.load(), isNull);
  });

  test('drops a novel entry containing non-string paths', () async {
    SharedPreferences.setMockInitialValues({
      'lore.agent.linked_outlines': jsonEncode({
        'schemaVersion': 1,
        'byNovelId': {
          'novel-a': ['ok.md', 42, null],
          'novel-b': ['b.md'],
        },
      }),
    });
    final loaded = await repository.load();
    expect(loaded, isNotNull);
    // 整条 novel 含非法元素 → 整体丢弃，其余小说保留。
    expect(loaded!.forNovel('novel-a'), isEmpty);
    expect(loaded.forNovel('novel-b'), ['b.md']);
  });
}
