import 'package:flutter_test/flutter_test.dart';
import 'package:lore_editor/lore_editor.dart';

void main() {
  group('EditorStyle.titleBottomSpacing', () {
    test('always exceeds paragraphSpacing across the slider range', () {
      // 段间距滑块允许 0–40；标题留白 = 段间距 + _titleGapExtra，必须始终严格
      // 更大，否则标题会与首段视觉粘连——这是 titleBottomSpacing 改为派生
      // getter 要锁定的核心不变量。未来若有人把 _titleGapExtra 改成 0 或负数，
      // 此测试会立即变红。
      for (final spacing in [0.0, 6.0, 14.0, 24.0, 40.0]) {
        final style = const EditorStyle.defaults().copyWith(
          paragraphSpacing: spacing,
        );
        expect(
          style.titleBottomSpacing,
          greaterThan(style.paragraphSpacing),
          reason: 'paragraphSpacing=$spacing',
        );
      }
    });

    test('default title gap is derived from default paragraph spacing', () {
      // 锁住派生关系：默认段间距 14 → 标题留白 28。防止被改回独立常量后，
      // 标题间距不再随段间距跟踪，重新出现「标题间距 < 段间距」的比例倒挂。
      const style = EditorStyle.defaults();
      expect(style.paragraphSpacing, 14);
      expect(style.titleBottomSpacing, 28);
    });
  });
}
