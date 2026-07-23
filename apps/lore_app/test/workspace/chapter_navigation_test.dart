import 'package:flutter_test/flutter_test.dart';
import 'package:lore_app/features/workspace/chapter_navigation.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:path/path.dart' as p;

const _bodyId = ContentId('b0000000-0000-4000-8000-0000000000bb');
const _novelId = NovelId('n0000000-0000-4000-8000-0000000000nn');

ContentNode _chapter(ContentId id, ContentId parent, String path, int order) =>
    ContentNode(
      id: id,
      parentId: parent,
      type: ContentNodeType.chapter,
      relativePath: path,
      order: order,
      number: order + 1,
      role: ContentRole.normal,
    );

NovelSnapshot _novel({
  required List<ContentNode> nodes,
  String title = '长夜行',
}) {
  return NovelSnapshot(
    rootPath: title,
    metadata: NovelMetadata(
      schemaVersion: 2,
      revision: 0,
      id: _novelId,
      title: title,
      description: '',
      coverPath: null,
      body: const NovelBody(id: _bodyId, relativePath: '正文'),
      chapterFormat: ChapterFormat.markdown,
      numberingMode: NumberingMode.continuous,
      createdAt: DateTime.utc(2026, 7, 21),
      updatedAt: DateTime.utc(2026, 7, 21),
    ),
    contentTree: ContentTree(
      schemaVersion: 2,
      novelId: _novelId,
      revision: 0,
      nodes: nodes,
    ),
  );
}

/// 混合结构：1 个正文根级章节 + 两个卷（各含章节），节点存储顺序被打乱。
///
/// 阅读顺序应为：[chRoot, chV1A, chV1B, chV2A]（根级在前，卷按 order 升序，
/// 卷内章节按 order 升序）。
NovelSnapshot _buildMixedNovel() {
  const vol1 = ContentId('v0000000-0000-4000-8000-000000000011');
  const vol2 = ContentId('v0000000-0000-4000-8000-000000000022');
  const vol1Node = ContentNode(
    id: vol1,
    parentId: _bodyId,
    type: ContentNodeType.volume,
    relativePath: '正文/第一卷',
    order: 1,
    number: 1,
    role: ContentRole.normal,
  );
  const vol2Node = ContentNode(
    id: vol2,
    parentId: _bodyId,
    type: ContentNodeType.volume,
    relativePath: '正文/第二卷',
    order: 2,
    number: 2,
    role: ContentRole.normal,
  );
  return _novel(
    nodes: [
      // 故意打乱存储顺序：验证结果不依赖 nodes 顺序，只依赖 order / parentId。
      _chapter(
        const ContentId('c0000000-0000-4000-8000-0000000000a2'),
        vol2,
        '正文/第二卷/第三章.md',
        0,
      ),
      vol2Node,
      _chapter(
        const ContentId('c0000000-0000-4000-8000-0000000000b1'),
        vol1,
        '正文/第一卷/第二章.md',
        1,
      ),
      _chapter(
        const ContentId('c0000000-0000-4000-8000-0000000000r0'),
        _bodyId,
        '正文/序章.md',
        0,
      ),
      vol1Node,
      _chapter(
        const ContentId('c0000000-0000-4000-8000-0000000000a1'),
        vol1,
        '正文/第一卷/第一章.md',
        0,
      ),
    ],
  );
}

/// 全卷结构：两个卷、无正文根级章节，且卷内章节 order 乱序。
NovelSnapshot _buildVolumesOnlyNovel() {
  const vol1 = ContentId('v0000000-0000-4000-8000-000000000011');
  const vol2 = ContentId('v0000000-0000-4000-8000-000000000022');
  const vol1Node = ContentNode(
    id: vol1,
    parentId: _bodyId,
    type: ContentNodeType.volume,
    relativePath: '正文/第一卷',
    order: 1,
    number: 1,
    role: ContentRole.normal,
  );
  const vol2Node = ContentNode(
    id: vol2,
    parentId: _bodyId,
    type: ContentNodeType.volume,
    relativePath: '正文/第二卷',
    order: 2,
    number: 2,
    role: ContentRole.normal,
  );
  return _novel(
    nodes: [
      vol2Node,
      vol1Node,
      // 卷一内 order 故意乱序 [3,1,2]，验证 childrenOf 的 order 排序。
      _chapter(
        const ContentId('c0000000-0000-4000-8000-0000000000v1c'),
        vol1,
        '正文/第一卷/第三节.md',
        3,
      ),
      _chapter(
        const ContentId('c0000000-0000-4000-8000-0000000000v1a'),
        vol1,
        '正文/第一卷/第一节.md',
        1,
      ),
      _chapter(
        const ContentId('c0000000-0000-4000-8000-0000000000v1b'),
        vol1,
        '正文/第一卷/第二节.md',
        2,
      ),
      _chapter(
        const ContentId('c0000000-0000-4000-8000-0000000000v2a'),
        vol2,
        '正文/第二卷/第一节.md',
        0,
      ),
    ],
  );
}

/// 单章全书：仅 1 个正文根级章节。
NovelSnapshot _buildSingleChapterNovel() {
  return _novel(
    nodes: [
      _chapter(
        const ContentId('c0000000-0000-4000-8000-0000000000only'),
        _bodyId,
        '正文/唯一章.md',
        0,
      ),
    ],
  );
}

void main() {
  group('chaptersInReadingOrder', () {
    test('根级章节在前，其后各卷按 order 升序、卷内章节按 order 升序', () {
      final ordered = chaptersInReadingOrder(_buildMixedNovel());
      expect(
        ordered.map((node) => node.relativePath).toList(),
        [
          '正文/序章.md',
          '正文/第一卷/第一章.md',
          '正文/第一卷/第二章.md',
          '正文/第二卷/第三章.md',
        ],
      );
    });

    test('忽略存储顺序：结果稳定', () {
      final novel = _buildMixedNovel();
      final first = chaptersInReadingOrder(novel);
      final second = chaptersInReadingOrder(novel);
      expect(second.map((e) => e.id), first.map((e) => e.id));
    });

    test('全卷结构无根级章节：仅卷段填充，卷内 order 乱序被修正', () {
      final ordered = chaptersInReadingOrder(_buildVolumesOnlyNovel());
      expect(
        ordered.map((node) => node.relativePath).toList(),
        [
          '正文/第一卷/第一节.md',
          '正文/第一卷/第二节.md',
          '正文/第一卷/第三节.md',
          '正文/第二卷/第一节.md',
        ],
      );
    });
  });

  group('computeChapterNavigation', () {
    final novel = _buildMixedNovel();
    final tree = novel.contentTree;

    test('首章无上一章，正文根级章节卷归属为 null', () {
      final first = tree.nodeById(
        const ContentId('c0000000-0000-4000-8000-0000000000r0'),
      )!;
      final nav = computeChapterNavigation(novel, first)!;
      expect(nav.index, 0);
      expect(nav.total, 4);
      expect(nav.volumeId, isNull);
      expect(nav.hasPrevious, isFalse);
      expect(nav.nextPath, p.join('长夜行', '正文/第一卷/第一章.md'));
    });

    test('中间章给出上一/下一章路径，跨卷衔接', () {
      // 第一卷末章 → 下一章跨到第二卷首章。
      final middle = tree.nodeById(
        const ContentId('c0000000-0000-4000-8000-0000000000b1'),
      )!;
      final nav = computeChapterNavigation(novel, middle)!;
      expect(nav.index, 2);
      expect(nav.total, 4);
      expect(
        nav.volumeId,
        const ContentId('v0000000-0000-4000-8000-000000000011'),
      );
      expect(nav.previousPath, p.join('长夜行', '正文/第一卷/第一章.md'));
      expect(nav.nextPath, p.join('长夜行', '正文/第二卷/第三章.md'));
    });

    test('末章无下一章', () {
      final last = tree.nodeById(
        const ContentId('c0000000-0000-4000-8000-0000000000a2'),
      )!;
      final nav = computeChapterNavigation(novel, last)!;
      expect(nav.index, 3);
      expect(nav.hasNext, isFalse);
      expect(nav.hasPrevious, isTrue);
    });

    test('单章全书：首章即末章，无上一/下一章', () {
      final single = _buildSingleChapterNovel();
      final only = single.contentTree.nodeById(
        const ContentId('c0000000-0000-4000-8000-0000000000only'),
      )!;
      final nav = computeChapterNavigation(single, only)!;
      expect(nav.index, 0);
      expect(nav.total, 1);
      expect(nav.hasPrevious, isFalse);
      expect(nav.hasNext, isFalse);
      expect(nav.volumeId, isNull);
    });

    test('节点不属于该小说章节序列时返回 null', () {
      final stray = ContentNode(
        id: const ContentId('unknown'),
        parentId: const ContentId('unknown'),
        type: ContentNodeType.chapter,
        relativePath: '别处.md',
        order: 0,
        number: 1,
        role: ContentRole.normal,
      );
      expect(computeChapterNavigation(novel, stray), isNull);
    });
  });
}
