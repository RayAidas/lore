import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_editor/lore_editor.dart';

Highlight _hl(int start, int end, {String id = 'h', int color = 0xFFFFD54F}) {
  return Highlight(
    id: id,
    start: start,
    end: end,
    colorArgb: color,
    anchorText: 'x' * (end - start).clamp(1, 8),
  );
}

void main() {
  group('LoreLargeTextController highlight maintenance', () {
    test('replaceSelection 在高亮前插入 → 高亮整体右移', () {
      final c = LoreLargeTextController(text: '0123456789');
      c.setHighlights([_hl(2, 5)]);
      c.selection = const TextSelection.collapsed(offset: 0);
      c.replaceSelection('AB'); // 在 0 插入 2 字
      expect(c.highlights.first.start, 4);
      expect(c.highlights.first.end, 7);
      c.dispose();
    });

    test('replaceRange 删除高亮前文字 → 高亮左移', () {
      final c = LoreLargeTextController(text: '0123456789');
      c.setHighlights([_hl(3, 6)]);
      c.replaceRange(0, 2, ''); // 删 [0,2)
      expect(c.highlights.first.start, 1);
      expect(c.highlights.first.end, 4);
      c.dispose();
    });

    test('replaceRange 删除覆盖高亮中部 → 收缩右端', () {
      final c = LoreLargeTextController(text: '0123456789');
      c.setHighlights([_hl(2, 8)]);
      c.replaceRange(4, 6, ''); // 删 [4,6),高亮 [2,8) → [2,6)
      expect(c.highlights.first.start, 2);
      expect(c.highlights.first.end, 6);
      c.dispose();
    });

    test('replaceRange 删除吞噬高亮 → 丢弃', () {
      final c = LoreLargeTextController(text: '0123456789');
      c.setHighlights([_hl(3, 6)]);
      c.replaceRange(2, 7, ''); // 删 [2,7),完全覆盖 [3,6)
      expect(c.highlights, isEmpty);
      c.dispose();
    });

    test('undo/redo → 高亮跟随正向与反向', () {
      final c = LoreLargeTextController(text: '0123456789');
      c.setHighlights([_hl(2, 5)]);
      c.selection = const TextSelection.collapsed(offset: 0);
      c.replaceSelection('AB'); // [2,5) → [4,7)
      expect(c.highlights.first.start, 4);
      c.undo(); // 撤销插入 → [4,7) → [2,5)
      expect(c.highlights.first.start, 2);
      expect(c.highlights.first.end, 5);
      c.redo(); // 重做插入 → [2,5) → [4,7)
      expect(c.highlights.first.start, 4);
      c.dispose();
    });

    test('replaceAllText → 高亮按全量替换维护', () {
      final c = LoreLargeTextController(text: '0123456789');
      c.setHighlights([_hl(8, 10)]);
      // 全量替换为更短文本:[0,10) del, add 'abc'(3)。高亮 [8,10) 落删除区→丢弃。
      c.replaceAllText('abc');
      expect(c.highlights, isEmpty);
      c.dispose();
    });

    test('setHighlights 设置并通知,相同列表不重复通知', () {
      final c = LoreLargeTextController(text: 'abc');
      var notified = 0;
      c.addListener(() => notified++);
      c.setHighlights([_hl(0, 2)]);
      expect(c.highlights, hasLength(1));
      expect(notified, 1);
      c.setHighlights([_hl(0, 2)]); // 等值 → 不通知
      expect(notified, 1);
      c.setHighlights([_hl(1, 3)]); // 不同 → 通知
      expect(notified, 2);
      c.dispose();
    });

    test('无高亮时空列表不变(编辑不引入)', () {
      final c = LoreLargeTextController(text: '0123456789');
      c.selection = const TextSelection.collapsed(offset: 0);
      c.replaceSelection('AB');
      expect(c.highlights, isEmpty);
      c.dispose();
    });
  });
}
