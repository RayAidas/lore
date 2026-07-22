import 'package:lore_domain/lore_domain.dart';
import 'package:test/test.dart';

/// 用段落文本本身派生确定性 digest(相同文本 → 相同 digest),聚焦 LCS 对齐
/// 与重定位逻辑,不依赖真实 sha256(那是 application 层的职责)。
List<String> digests(List<String> paras) {
  return [for (final p in paras) 'd:$p:${p.length}'];
}

/// 由段落列表计算全局 offset 范围(段间一个 `\n`)。
List<ParagraphSpan> spansFor(List<String> paras) {
  final out = <ParagraphSpan>[];
  var acc = 0;
  for (final p in paras) {
    out.add(paragraphSpan(acc, acc + p.length));
    acc += p.length + 1;
  }
  return out;
}

/// 在 oldParas 的第 [paraIdx] 段、局部起点 [localStart] 构造一条高亮,
/// anchorText 自动取该段对应子串(length 超出段尾时自动夹紧)。
Highlight highlightIn(
  List<String> oldParas,
  int paraIdx,
  int localStart,
  int length, {
  String id = 'h',
  int color = 0xFFFFD54F,
}) {
  final spans = spansFor(oldParas);
  final span = spans[paraIdx];
  final text = oldParas[paraIdx];
  final avail = text.length - localStart;
  final len = length > avail ? avail : length;
  final anchor = text.substring(localStart, localStart + len);
  return Highlight(
    id: id,
    start: span.start + localStart,
    end: span.start + localStart + len,
    colorArgb: color,
    anchorText: anchor,
  );
}

ReconcileResult reconcile(
  List<String> oldParas,
  List<String> newParas,
  List<Highlight> highlights,
) {
  return reconcileHighlights(
    oldDigests: digests(oldParas),
    newDigests: digests(newParas),
    newParagraphTexts: newParas,
    oldParagraphSpans: spansFor(oldParas),
    oldHighlights: highlights,
  );
}

void main() {
  group('reconcileHighlights - 文档未变或无关变更', () {
    test('old==new → 全部 located,anchor 完好', () {
      const paras = ['第一段文字', '第二段文字', '第三段文字'];
      final h = highlightIn(paras, 1, 2, 2);
      final result = reconcile(paras, paras, [h]);
      expect(result.lost, isEmpty);
      expect(result.located, hasLength(1));
      expect(result.located.first.anchorText, h.anchorText);
    });

    test('高亮所在段未改、别处改字 → located、anchor 完好', () {
      const old = ['第一段', '第二段高亮', '第三段'];
      const next = ['第一段改了', '第二段高亮', '第三段'];
      final h = highlightIn(old, 1, 0, 5); // 整段 "第二段高亮"
      final result = reconcile(old, next, [h]);
      expect(result.lost, isEmpty);
      expect(result.located, hasLength(1));
      expect(result.located.first.anchorText, '第二段高亮');
    });

    test('空高亮列表 → empty 结果', () {
      const paras = ['a', 'b'];
      final result = reconcile(paras, paras, const []);
      expect(result.located, isEmpty);
      expect(result.lost, isEmpty);
    });
  });

  group('reconcileHighlights - 段内修改', () {
    test('高亮段改字、anchor 失配 → lost', () {
      const old = ['原文高亮字'];
      const next = ['原文改字']; // "高亮" 被改成 "改字"
      final h = highlightIn(old, 0, 2, 2); // "高亮"
      final result = reconcile(old, next, [h]);
      expect(result.located, isEmpty);
      expect(result.lost, hasLength(1));
    });

    test('高亮段首加字、anchor 完好 → located 重定位', () {
      const old = ['前缀高亮后缀'];
      const next = ['改动前缀高亮后缀']; // 段首加字,anchor "高亮" 仍在
      final h = highlightIn(old, 0, 2, 2); // "高亮"
      final result = reconcile(old, next, [h]);
      expect(result.lost, isEmpty);
      expect(result.located.first.anchorText, '高亮');
      // 新段中 "高亮" 在 localStart = "改动前缀".length = 4。
      expect(result.located.first.start, 4);
      expect(result.located.first.end, 6);
    });
  });

  group('reconcileHighlights - 段落增删与移动', () {
    test('高亮段被剪切挪到末尾 → located 跟随到新位置', () {
      const old = ['段A', '段B高亮', '段C'];
      const next = ['段A', '段C', '段B高亮']; // B 挪到末尾
      final h = highlightIn(old, 1, 2, 2); // "高亮" 在段B
      final result = reconcile(old, next, [h]);
      expect(result.lost, isEmpty);
      // 段B现在在 index2,起点 = '段A'(2)+1 + '段C'(2)+1 = 6,"高亮" 在 +2。
      expect(result.located.first.start, 8);
      expect(result.located.first.end, 10);
      expect(result.located.first.anchorText, '高亮');
    });

    test('高亮所在段被删除 → lost', () {
      const old = ['段A', '段B高亮', '段C'];
      const next = ['段A', '段C']; // B 被删
      final h = highlightIn(old, 1, 0, 2); // "段B"
      final result = reconcile(old, next, [h]);
      expect(result.located, isEmpty);
      expect(result.lost, hasLength(1));
    });

    test('高亮段前插入新段 → located', () {
      const old = ['段A高亮', '段B'];
      const next = ['新段', '段A高亮', '段B'];
      final h = highlightIn(old, 0, 2, 2); // "高亮"
      final result = reconcile(old, next, [h]);
      expect(result.lost, isEmpty);
      expect(result.located.first.anchorText, '高亮');
    });

    test('高亮段前删除一段 → located', () {
      const old = ['段X', '段A高亮', '段B'];
      const next = ['段A高亮', '段B'];
      final h = highlightIn(old, 1, 2, 2);
      final result = reconcile(old, next, [h]);
      expect(result.lost, isEmpty);
      expect(result.located.first.anchorText, '高亮');
    });
  });

  group('reconcileHighlights - 锚点歧义与短锚点', () {
    test('anchor 多次命中 → 按旧段内比例消歧', () {
      const old = ['他说你好他说你好']; // "他说" 出现两次
      final h = highlightIn(old, 0, 4, 2); // 第二个 "他说"(localStart=4)
      final result = reconcile(old, old, [h]);
      expect(result.lost, isEmpty);
      // 旧 localStart=4 在长度 8 段中比例 0.5,期望位置 4,第二个命中。
      expect(result.located.first.start, 4);
    });

    test('短 anchor 在新段唯一命中 → located(indexOf 重定位)', () {
      const old = ['abcdefgh'];
      const next = ['abcDefgh']; // 长度不变、字符变了
      final h = highlightIn(old, 0, 1, 1); // "b"
      final result = reconcile(old, next, [h]);
      expect(result.lost, isEmpty);
      expect(result.located, hasLength(1));
      expect(result.located.first.start, 1);
    });
  });

  group('reconcileHighlights - 跨段与重写', () {
    test('跨段高亮 → lost(本版不支持)', () {
      const old = ['段A', '段B'];
      final spans = spansFor(old);
      final h = Highlight(
        id: 'cross',
        start: spans[0].start,
        end: spans[1].end,
        colorArgb: 0xFFFFD54F,
        anchorText: '跨段',
      );
      final result = reconcile(old, old, [h]);
      expect(result.located, isEmpty);
      expect(result.lost, hasLength(1));
    });

    test('整篇重写 → 全 lost', () {
      const old = ['原文一', '原文二'];
      const next = ['完全不同的内容', '毫不相干'];
      final highlights = [highlightIn(old, 0, 0, 2), highlightIn(old, 1, 0, 2)];
      final result = reconcile(old, next, highlights);
      expect(result.located, isEmpty);
      expect(result.lost, hasLength(2));
    });
  });

  group('alignParagraphs', () {
    test('无重复段 → 一一对应', () {
      final a = alignParagraphs(['A', 'B', 'C'], ['A', 'B', 'C']);
      expect(a[0], 0);
      expect(a[1], 1);
      expect(a[2], 2);
    });

    test('段被删 → 对应 null', () {
      final a = alignParagraphs(['A', 'B', 'C'], ['A', 'C']);
      expect(a[0], 0);
      expect(a[1], isNull);
      expect(a[2], 1);
    });

    test('相邻段交换 → 三层对齐后均匹配', () {
      final a = alignParagraphs(['A', 'B', 'C'], ['B', 'A', 'C']);
      expect(a[0], 1); // A 现在在 index1
      expect(a[1], 0); // B 现在在 index0
      expect(a[2], 2);
    });
  });
}
