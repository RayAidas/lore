import 'package:lore_domain/lore_domain.dart';
import 'package:test/test.dart';

void main() {
  group('AppPreferences', () {
    test(
      'defaults to wenkai font for an out-of-the-box reading experience',
      () {
        expect(
          AppPreferences.defaults().editorFontFamily,
          AppFontFamily.wenkai,
        );
      },
    );

    test('copyWith updates editorFontFamily without touching other fields', () {
      final base = AppPreferences.defaults();
      final updated = base.copyWith(editorFontFamily: AppFontFamily.serif);

      expect(updated.editorFontFamily, AppFontFamily.serif);
      // 其余字段保持不变。
      expect(updated.themeMode, base.themeMode);
      expect(updated.editorFontSize, base.editorFontSize);
      expect(updated.editorLineHeight, base.editorLineHeight);
      expect(updated.firstLineIndent, base.firstLineIndent);
    });

    test('copyWith leaves editorFontFamily unchanged when omitted', () {
      final base = AppPreferences.defaults().copyWith(
        editorFontFamily: AppFontFamily.kai,
      );
      final updated = base.copyWith(editorFontSize: 20);

      expect(updated.editorFontFamily, AppFontFamily.kai);
      expect(updated.editorFontSize, 20);
    });
  });
}
