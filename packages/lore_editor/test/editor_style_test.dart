import 'package:flutter_test/flutter_test.dart';
import 'package:lore_editor/lore_editor.dart';

void main() {
  group('EditorStyle.titleBottomSpacing', () {
    test(
      'always exceeds rendered paragraph gap across the multiplier range',
      () {
        // 段间距现在是字号倍数，渲染段距 = 倍数 × 字号；标题留白 =
        // (paragraphSpacing + _titleGapExtra) × fontSize，必须始终严格大于渲染
        // 段距，否则标题会与首段视觉粘连——这是 titleBottomSpacing 作为派生
        // getter 要锁定的核心不变量。未来若有人把 _titleGapExtra 改成 0 或负数，
        // 此测试会立即变红。
        const defaults = EditorStyle.defaults();
        for (final spacing in [0.0, 0.5, 1.2, 2.0, 3.0]) {
          final style = defaults.copyWith(paragraphSpacing: spacing);
          expect(
            style.titleBottomSpacing,
            greaterThan(spacing * defaults.fontSize),
            reason: 'paragraphSpacing=$spacing',
          );
        }
      },
    );

    test('default title gap is derived from default paragraph spacing', () {
      // 锁住派生关系：默认字号 18、段间距 1.2（字号倍数）→ 标题留白
      // (1.2 + 1.0) × 18 = 39.6。防止被改回独立常量后，标题间距不再随段间距
      // 跟踪，重新出现「标题间距 < 段间距」的比例倒挂。
      const style = EditorStyle.defaults();
      expect(style.fontSize, 18);
      expect(style.paragraphSpacing, 1.2);
      expect(style.titleBottomSpacing, 39.6);
    });
  });
}
