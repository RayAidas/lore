import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:test/test.dart';

void main() {
  const bodyId = ContentId('body');
  final novelId = const NovelId('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');

  ContentNode chapter({
    required String id,
    required String path,
    int? number,
    ContentId? parent,
    int order = 1000,
    ContentRole role = ContentRole.normal,
  }) {
    return ContentNode(
      id: ContentId(id),
      type: ContentNodeType.chapter,
      parentId: parent ?? bodyId,
      relativePath: path,
      order: order,
      number: number,
      role: role,
    );
  }

  ContentNode volume({
    required String id,
    String path = '正文/第一卷',
    int? number,
    int order = 1000,
  }) {
    return ContentNode(
      id: ContentId(id),
      type: ContentNodeType.volume,
      parentId: bodyId,
      relativePath: path,
      order: order,
      number: number,
      role: ContentRole.normal,
    );
  }

  ContentTree treeWith(List<ContentNode> nodes) => ContentTree(
    schemaVersion: 1,
    novelId: novelId,
    revision: 1,
    nodes: nodes,
  );

  group('parseMemoryEntries', () {
    test('splits sections, ignores the header, and recognizes every key form',
        () {
      final entries = parseMemoryEntries('''
# 章节记忆
> 基于 4 章生成 · 2026-08-11

## 第3章 觉醒
林晚在黎明醒来。

## 未分卷 第1章 序篇
正文根级章节。

## 第1卷 第2章 重逢
她在桥头出现。

## 序章
前情提要。

## 后记
结语。

## 番外一
小剧场。

## 无法识别的标题
不透明条目。
''');

      expect(entries, hasLength(7));
      expect(entries[0].heading, '第3章 觉醒');
      expect(entries[0].body, '林晚在黎明醒来。');
      expect(
        entries[0].key,
        const MemoryKeyNumbered(volume: null, number: 3),
      );
      expect(
        entries[1].key,
        const MemoryKeyNumbered(volume: null, number: 1),
      );
      expect(entries[1].heading, '未分卷 第1章 序篇');
      expect(
        entries[2].key,
        const MemoryKeyNumbered(volume: 1, number: 2),
      );
      expect(entries[2].heading, '第1卷 第2章 重逢');
      expect(entries[3].key, const MemoryKeyRole('序章'));
      expect(entries[4].key, const MemoryKeyRole('后记'));
      expect(entries[5].key, const MemoryKeyRole('番外一'));
      expect(entries[6].key, isNull);
      expect(entries[6].heading, '无法识别的标题');
      expect(entries[6].body, '不透明条目。');
      // 头部行不落入任何条目的正文。
      expect(entries.map((e) => e.body), isNot(contains('章节记忆')));
    });

    test('keeps multi-paragraph bodies and trims section whitespace', () {
      final entries = parseMemoryEntries('''
## 第1章 觉醒
第一段。

第二段。
''');
      expect(entries, hasLength(1));
      expect(entries.single.body, '第一段。\n\n第二段。');
      expect(entries.single.raw, '## 第1章 觉醒\n第一段。\n\n第二段。');
    });

    test('returns empty for a document without any section headings', () {
      expect(parseMemoryEntries('# 章节记忆\n> 基于 1 章生成'), isEmpty);
      expect(parseMemoryEntries(''), isEmpty);
    });

    test('ignores `### ` headings as body content', () {
      final entries = parseMemoryEntries('''
## 第1章 觉醒
### 伏笔
剑。
''');
      expect(entries, hasLength(1));
      expect(entries.single.body, contains('### 伏笔'));
    });
  });

  group('hasDuplicateKeys', () {
    MemoryEntry entry(String heading) {
      final raw = '## $heading\n正文';
      return MemoryEntry(
        heading: heading,
        body: '正文',
        key: parseMemoryEntries(raw).single.key,
        raw: raw,
      );
    }

    test('detects repeated anchors', () {
      expect(
        hasDuplicateKeys([entry('第1章'), entry('第1章')]),
        isTrue,
      );
    });

    test('ignores opaque entries and distinct keys', () {
      expect(
        hasDuplicateKeys([
          entry('第1章'),
          entry('第2章'),
          entry('无法识别的标题'),
        ]),
        isFalse,
      );
    });
  });

  group('memoryKeyForNode', () {
    test('continuous mode yields a bare numbered key', () {
      final node = chapter(id: 'c1', path: '正文/第3章.md', number: 3);
      final key = memoryKeyForNode(
        node: node,
        mode: NumberingMode.continuous,
        tree: treeWith([node]),
      );
      expect(key, const MemoryKeyNumbered(volume: null, number: 3));
    });

    test('perVolume qualifies the key with the volume number', () {
      final vol = volume(id: 'v1', number: 1);
      final node = chapter(
        id: 'c1',
        path: '正文/第一卷/第3章.md',
        number: 3,
        parent: vol.id,
      );
      final key = memoryKeyForNode(
        node: node,
        mode: NumberingMode.perVolume,
        tree: treeWith([vol, node]),
      );
      expect(key, const MemoryKeyNumbered(volume: 1, number: 3));
    });

    test('perVolume body-level chapters stay unvolumed', () {
      final node = chapter(id: 'c1', path: '正文/第1章.md', number: 1);
      final key = memoryKeyForNode(
        node: node,
        mode: NumberingMode.perVolume,
        tree: treeWith([node]),
      );
      expect(key, const MemoryKeyNumbered(volume: null, number: 1));
    });

    test('perVolume with an unnumbered volume directory stays unvolumed', () {
      final vol = volume(id: 'v1', path: '正文/第一卷', number: null);
      final node = chapter(
        id: 'c1',
        path: '正文/第一卷/第1章.md',
        number: 1,
        parent: vol.id,
      );
      final key = memoryKeyForNode(
        node: node,
        mode: NumberingMode.perVolume,
        tree: treeWith([vol, node]),
      );
      expect(key, const MemoryKeyNumbered(volume: null, number: 1));
    });

    test('role chapters are keyed by the file name stem', () {
      final prologue = chapter(
        id: 'p',
        path: '正文/序章.md',
        number: null,
        role: ContentRole.prologue,
      );
      final extra = chapter(
        id: 'e',
        path: '正文/番外一.md',
        number: null,
        role: ContentRole.extra,
      );
      final tree = treeWith([prologue, extra]);
      expect(
        memoryKeyForNode(node: prologue, mode: NumberingMode.continuous, tree: tree),
        const MemoryKeyRole('序章'),
      );
      expect(
        memoryKeyForNode(node: extra, mode: NumberingMode.continuous, tree: tree),
        const MemoryKeyRole('番外一'),
      );
    });
  });

  group('canonicalHeadingFor', () {
    test('continuous includes the subtitle when present', () {
      final node = chapter(id: 'c1', path: '正文/第3章.md', number: 3);
      expect(
        canonicalHeadingFor(
          node: node,
          mode: NumberingMode.continuous,
          tree: treeWith([node]),
          subtitle: '觉醒',
        ),
        '第3章 觉醒',
      );
      expect(
        canonicalHeadingFor(
          node: node,
          mode: NumberingMode.continuous,
          tree: treeWith([node]),
          subtitle: '  ',
        ),
        '第3章',
      );
    });

    test('perVolume prefixes the volume number', () {
      final vol = volume(id: 'v1', number: 1);
      final node = chapter(
        id: 'c1',
        path: '正文/第一卷/第3章.md',
        number: 3,
        parent: vol.id,
      );
      expect(
        canonicalHeadingFor(
          node: node,
          mode: NumberingMode.perVolume,
          tree: treeWith([vol, node]),
          subtitle: '觉醒',
        ),
        '第1卷 第3章 觉醒',
      );
    });

    test('perVolume body-level falls back to 未分卷', () {
      final node = chapter(id: 'c1', path: '正文/第1章.md', number: 1);
      expect(
        canonicalHeadingFor(
          node: node,
          mode: NumberingMode.perVolume,
          tree: treeWith([node]),
          subtitle: '',
        ),
        '未分卷 第1章',
      );
    });

    test('role chapters use the file name stem only', () {
      final node = chapter(
        id: 'p',
        path: '正文/序章.md',
        number: null,
        role: ContentRole.prologue,
      );
      expect(
        canonicalHeadingFor(
          node: node,
          mode: NumberingMode.continuous,
          tree: treeWith([node]),
          subtitle: '',
        ),
        '序章',
      );
    });
  });

  group('mergeEntries', () {
    MemoryEntry entry(String heading, String body) {
      final raw = '## $heading\n$body';
      return MemoryEntry(
        heading: heading,
        body: body,
        key: parseMemoryEntries(raw).single.key,
        raw: raw,
      );
    }

    test('replaces matching targets in place and preserves the rest verbatim',
        () {
      final existing = [
        entry('第1章', '旧摘要1（手改）'),
        entry('第2章', '摘要2'),
      ];
      final updates = [entry('第1章', '新摘要1')];

      final merged = mergeEntries(existing: existing, updates: updates);

      expect(merged, hasLength(2));
      expect(merged[0].heading, '第1章');
      expect(merged[0].body, '新摘要1');
      expect(merged[1].body, '摘要2');
      expect(merged[1].raw, existing[1].raw);
    });

    test('appends new targets at the end', () {
      final existing = [entry('第1章', '摘要1')];
      final updates = [entry('第3章', '摘要3'), entry('第2章', '摘要2')];

      final merged = mergeEntries(existing: existing, updates: updates);

      expect(merged, hasLength(3));
      expect(merged[0].body, '摘要1');
      expect(merged[1].heading, '第3章');
      expect(merged[2].heading, '第2章');
    });

    test('keeps opaque entries untouched', () {
      final existing = [
        entry('第1章', '摘要1'),
        entry('手写备注', '不要动我'),
      ];
      final updates = [entry('第1章', '新摘要1')];

      final merged = mergeEntries(existing: existing, updates: updates);

      expect(merged, hasLength(2));
      expect(merged[0].body, '新摘要1');
      expect(merged[1].raw, existing[1].raw);
    });
  });

  group('formatMemoryDoc', () {
    test('wraps entries with the fixed header and blank-line separators', () {
      MemoryEntry entry(String heading, String body) => MemoryEntry(
        heading: heading,
        body: body,
        raw: '## $heading\n$body',
      );
      final text = formatMemoryDoc(
        [entry('第1章', 'a'), entry('第2章', 'b')],
        chapterCount: 2,
        now: DateTime.utc(2026, 8, 11),
      );
      expect(text, startsWith('# 章节记忆'));
      expect(text, contains('> 基于 2 章生成 · 2026-08-11'));
      expect(text, contains('## 第1章\na'));
      expect(text, contains('## 第2章\nb'));
    });
  });
}
