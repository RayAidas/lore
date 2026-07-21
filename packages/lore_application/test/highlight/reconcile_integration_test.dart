import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:test/test.dart';

Highlight _hl(int start, int end, {String anchor = '高亮'}) {
  return Highlight(
    id: 'h',
    start: start,
    end: end,
    colorArgb: 0xFFFFD54F,
    anchorText: anchor,
  );
}

void main() {
  group('highlight reconcile integration', () {
    test('paragraphSpansFromDigests 与 computeParagraphProfile.spans 一致', () {
      const text = 'abc\ndefgh\nij';
      final profile = computeParagraphProfile(text);
      final rebuilt = paragraphSpansFromDigests(profile.digests);
      expect(rebuilt.length, profile.spans.length);
      for (var i = 0; i < profile.spans.length; i++) {
        expect(rebuilt[i].start, profile.spans[i].start);
        expect(rebuilt[i].end, profile.spans[i].end);
      }
    });

    test('外部改字在高亮段外 → 高亮段未变,located 且 offset 不变', () {
      const oldText = '第一段\n第二段高亮\n第三段';
      const newText = '第一段\n第二段高亮\n第三段改了';
      final old = computeParagraphProfile(oldText);
      final fresh = computeParagraphProfile(newText);
      // 高亮在第二段的 "高亮" 字(第二段高亮:高在 localStart 3)。
      final segBStart = old.spans[1].start;
      final h = _hl(segBStart + 3, segBStart + 5);
      final result = reconcileHighlights(
        oldDigests: old.digests,
        newDigests: fresh.digests,
        newParagraphTexts: fresh.texts,
        oldParagraphSpans: paragraphSpansFromDigests(old.digests),
        oldHighlights: [h],
      );
      expect(result.lost, isEmpty);
      expect(result.located.first.start, h.start);
      expect(result.located.first.anchorText, '高亮');
    });

    test('段落剪切移动 → 高亮跟随到新位置', () {
      const oldText = '段A\n段B高亮\n段C';
      const newText = '段A\n段C\n段B高亮'; // 段B 挪到末尾
      final old = computeParagraphProfile(oldText);
      final fresh = computeParagraphProfile(newText);
      final segBStart = old.spans[1].start;
      final h = _hl(segBStart + 2, segBStart + 4);
      final result = reconcileHighlights(
        oldDigests: old.digests,
        newDigests: fresh.digests,
        newParagraphTexts: fresh.texts,
        oldParagraphSpans: paragraphSpansFromDigests(old.digests),
        oldHighlights: [h],
      );
      expect(result.lost, isEmpty);
      // 段B 现在在新文档 index2,起点 = fresh.spans[2].start,"高亮" +2。
      expect(result.located.first.start, fresh.spans[2].start + 2);
      expect(result.located.first.anchorText, '高亮');
    });

    test('高亮所在段被删除 → lost', () {
      const oldText = '段A\n段B高亮\n段C';
      const newText = '段A\n段C'; // 段B 删
      final old = computeParagraphProfile(oldText);
      final fresh = computeParagraphProfile(newText);
      final segBStart = old.spans[1].start;
      final h = _hl(segBStart, segBStart + 2, anchor: '段B');
      final result = reconcileHighlights(
        oldDigests: old.digests,
        newDigests: fresh.digests,
        newParagraphTexts: fresh.texts,
        oldParagraphSpans: paragraphSpansFromDigests(old.digests),
        oldHighlights: [h],
      );
      expect(result.located, isEmpty);
      expect(result.lost, hasLength(1));
    });

    test('整篇重写为无关内容 → 全 lost', () {
      const oldText = '原文段落一\n原文段落二';
      const newText = '完全不同的内容\n毫不相干';
      final old = computeParagraphProfile(oldText);
      final fresh = computeParagraphProfile(newText);
      final h = _hl(old.spans[0].start, old.spans[0].end, anchor: '原文段落一');
      final result = reconcileHighlights(
        oldDigests: old.digests,
        newDigests: fresh.digests,
        newParagraphTexts: fresh.texts,
        oldParagraphSpans: paragraphSpansFromDigests(old.digests),
        oldHighlights: [h],
      );
      expect(result.located, isEmpty);
      expect(result.lost, hasLength(1));
    });

    test('段内首部加字、anchor 完好 → 重定位', () {
      const oldText = '前缀高亮后缀';
      const newText = '改动前缀高亮后缀';
      final old = computeParagraphProfile(oldText);
      final fresh = computeParagraphProfile(newText);
      final h = _hl(2, 4); // "高亮"
      final result = reconcileHighlights(
        oldDigests: old.digests,
        newDigests: fresh.digests,
        newParagraphTexts: fresh.texts,
        oldParagraphSpans: paragraphSpansFromDigests(old.digests),
        oldHighlights: [h],
      );
      expect(result.lost, isEmpty);
      // 新段 "高亮" 在 localStart = "改动前缀".length = 4。
      expect(result.located.first.start, 4);
    });
  });
}
