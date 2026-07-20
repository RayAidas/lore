import 'package:flutter_test/flutter_test.dart';
import 'package:lore_app/features/preferences/font_options.dart';
import 'package:lore_domain/lore_domain.dart';

void main() {
  group('AppFontOptions', () {
    test('registers an option for every AppFontFamily value', () {
      // 新增枚举值时若忘记在注册表登记，此测试会失败。
      for (final value in AppFontFamily.values) {
        expect(
          AppFontOptions.options.containsKey(value),
          isTrue,
          reason: 'AppFontFamily.$value 未在 AppFontOptions 注册',
        );
        expect(
          AppFontOptions.resolve(value).label,
          isNotEmpty,
          reason: 'AppFontFamily.$value 的 label 为空',
        );
      }
    });

    test(
      'non-system options carry a family and a non-empty fallback chain',
      () {
        for (final value in AppFontFamily.values) {
          if (value == AppFontFamily.system) {
            continue;
          }
          final option = AppFontOptions.resolve(value);
          expect(option.fontFamily, isNotEmpty, reason: '$value 缺 fontFamily');
          expect(
            option.fontFamilyFallback,
            isNotEmpty,
            reason: '$value 缺 fontFamilyFallback',
          );
        }
      },
    );

    test('bundled wenkai family matches pubspec asset name', () {
      // pubspec 声明的 family 是 'LXGWWenKai'，注册表必须与之精确一致，
      // 否则字体资源不会被命中、静默回退到系统字体。
      expect(
        AppFontOptions.resolve(AppFontFamily.wenkai).fontFamily,
        'LXGWWenKai',
      );
    });
  });
}
