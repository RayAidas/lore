import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_app/features/preferences/theme_options.dart';
import 'package:lore_domain/lore_domain.dart';

void main() {
  group('resolveAppliedTheme', () {
    test('system follows platform with separate light/dark schemes', () {
      final r = AppThemeOptions.resolveAppliedTheme(AppThemeMode.system);
      expect(r.themeMode, ThemeMode.system);
      // 双方案：亮 / 暗为不同实例，分别由 light() / dark() 提供。
      expect(identical(r.theme, r.darkTheme), isFalse);
      expect(r.theme.colorScheme.brightness, Brightness.light);
      expect(r.darkTheme.colorScheme.brightness, Brightness.dark);
    });

    test('explicit dark theme mirrors theme and darkTheme '
        '(regression: ink must not collapse to night)', () {
      // 选墨渊时 theme 与 darkTheme 必须都是墨渊（纯黑），而非硬编码的夜间（灰）。
      // 旧实现把 darkTheme 写死成 LoreTheme.dark()，会让墨渊退化成夜间。
      final r = AppThemeOptions.resolveAppliedTheme(AppThemeMode.ink);
      expect(identical(r.theme, r.darkTheme), isTrue);
      expect(r.themeMode, ThemeMode.dark);
      expect(r.theme.colorScheme.brightness, Brightness.dark);
      // 纯黑表面是墨渊的 OLED 卖点；夜间是灰 #191A1C，二者必须区分。
      expect(r.theme.colorScheme.surface, const Color(0xFF000000));
      expect(r.darkTheme.colorScheme.surface, const Color(0xFF000000));
    });

    test('explicit light theme uses ThemeMode.light', () {
      final r = AppThemeOptions.resolveAppliedTheme(AppThemeMode.frost);
      expect(identical(r.theme, r.darkTheme), isTrue);
      expect(r.themeMode, ThemeMode.light);
      expect(r.theme.colorScheme.brightness, Brightness.light);
    });

    test(
      'existing dark mode keeps the standard night palette (no regression)',
      () {
        final r = AppThemeOptions.resolveAppliedTheme(AppThemeMode.dark);
        expect(r.themeMode, ThemeMode.dark);
        expect(r.theme.colorScheme.surface, const Color(0xFF191A1C));
      },
    );
  });

  group('dataFor', () {
    // 穷举 switch：枚举新增却漏注册 → 编译失败。这里锁定各主题的关键表面色，
    // 防止配色被无意改坏（也顺带覆盖 L3 想锁的「墨渊必须纯黑」）。
    test('maps each theme to its palette surface', () {
      expect(
        AppThemeOptions.dataFor(AppThemeMode.frost).colorScheme.surface,
        const Color(0xFFEBF1F6),
      );
      expect(
        AppThemeOptions.dataFor(AppThemeMode.green).colorScheme.surface,
        const Color(0xFFCDE7D0),
      );
      expect(
        AppThemeOptions.dataFor(AppThemeMode.ink).colorScheme.surface,
        const Color(0xFF000000),
      );
    });
  });

  group('options registry', () {
    test('covers every named theme mode', () {
      final registered = AppThemeOptions.options
          .map((option) => option.mode)
          .toSet();
      for (final mode in AppThemeMode.values) {
        if (mode == AppThemeMode.system) {
          continue; // 跟随系统是模式，非具名主题，由卡片单独渲染。
        }
        expect(registered, contains(mode), reason: '$mode 未在卡片注册表中登记');
      }
    });

    test('labels are exactly two characters', () {
      for (final option in AppThemeOptions.options) {
        expect(option.label.length, 2, reason: '${option.mode} 的名字应为 2 字');
      }
    });
  });
}
