import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_platform_adapters/lore_platform_adapters.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferencesAppPreferencesRepository repository;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repository = SharedPreferencesAppPreferencesRepository();
  });

  test('returns null when nothing stored', () async {
    expect(await repository.load(), isNull);
  });

  test('round-trips all fields through save and load', () async {
    final original = AppPreferences.defaults().copyWith(
      themeMode: AppThemeMode.sepia,
      defaultChapterFormat: ChapterFormat.text,
      editorLineHeight: 2.1,
      editorFontSize: 18,
      editorContentWidth: 820,
      dailyWordGoal: 1500,
      findMatchCase: true,
      findUseRegex: true,
      typewriterMode: true,
      focusMode: true,
      firstLineIndent: false,
      paragraphSpacing: 24,
      editorFontFamily: AppFontFamily.serif,
    );

    await repository.save(original);

    final loaded = await repository.load();
    expect(loaded, isNotNull);
    expect(loaded!.themeMode, AppThemeMode.sepia);
    expect(loaded.defaultChapterFormat, ChapterFormat.text);
    expect(loaded.editorLineHeight, 2.1);
    expect(loaded.editorFontSize, 18);
    expect(loaded.editorContentWidth, 820);
    expect(loaded.dailyWordGoal, 1500);
    expect(loaded.findMatchCase, isTrue);
    expect(loaded.findUseRegex, isTrue);
    expect(loaded.typewriterMode, isTrue);
    expect(loaded.focusMode, isTrue);
    expect(loaded.firstLineIndent, isFalse);
    expect(loaded.paragraphSpacing, 24);
    expect(loaded.editorFontFamily, AppFontFamily.serif);
  });

  test(
    'loads legacy blob missing immersive toggles with other prefs intact',
    () async {
      // 模拟 1.x 版本写入的旧 blob：没有 typewriterMode/focusMode 键。
      // 应当加载成功：沉浸开关回退默认 false；v1→v2 迁移按值匹配——行高 2.2
      // 是自定义值（≠ v1 默认 1.5）故保留，段间距缺失则取 v2 默认；其余偏好不变。
      SharedPreferences.setMockInitialValues({
        'lore.app.preferences': jsonEncode({
          'schemaVersion': 1,
          'themeMode': 'sepia',
          'defaultChapterFormat': 'markdown',
          'editorLineHeight': 2.2,
          'editorFontSize': 19,
          'editorContentWidth': 760,
          'dailyWordGoal': 800,
          'findMatchCase': true,
          'findUseRegex': false,
        }),
      });

      final loaded = await repository.load();
      expect(loaded, isNotNull);
      expect(loaded!.themeMode, AppThemeMode.sepia);
      expect(loaded.defaultChapterFormat, ChapterFormat.markdown);
      expect(loaded.editorFontSize, 19);
      expect(loaded.dailyWordGoal, 800);
      expect(loaded.findMatchCase, isTrue);
      expect(loaded.typewriterMode, isFalse);
      expect(loaded.focusMode, isFalse);
      expect(loaded.firstLineIndent, isTrue);
      // 行高 2.2 是自定义值（≠ v1 默认）→ 保留；段间距缺失 → 回落 v2 默认。
      expect(loaded.editorLineHeight, 2.2);
      expect(
        loaded.paragraphSpacing,
        AppPreferences.defaults().paragraphSpacing,
      );
      // editorFontFamily 是后加字段，旧 blob 缺该键应回落默认值（文楷）。
      expect(loaded.editorFontFamily, AppFontFamily.wenkai);
    },
  );

  test('v1 blob at old typography defaults is bumped to v2 defaults', () async {
    // 行高/段间距仍停留在 v1 默认（1.5 / 12）→ 替换为 v2 默认；其余偏好不变。
    SharedPreferences.setMockInitialValues({
      'lore.app.preferences': jsonEncode({
        'schemaVersion': 1,
        'themeMode': 'system',
        'defaultChapterFormat': 'text',
        'editorLineHeight': 1.5,
        'editorFontSize': 15,
        'editorContentWidth': 900,
        'dailyWordGoal': 2000,
        'findMatchCase': false,
        'findUseRegex': false,
        'paragraphSpacing': 12,
      }),
    });
    final loaded = await repository.load();
    expect(loaded, isNotNull);
    expect(
      loaded!.editorLineHeight,
      AppPreferences.defaults().editorLineHeight,
    );
    expect(loaded.paragraphSpacing, AppPreferences.defaults().paragraphSpacing);
    expect(loaded.editorFontSize, 15);
    expect(loaded.themeMode, AppThemeMode.system);
  });

  test('v1 blob with customized spacing preserves user values', () async {
    // 用户自定义的行高/段间距（≠ v1 默认）原样保留，迁移不覆盖。
    SharedPreferences.setMockInitialValues({
      'lore.app.preferences': jsonEncode({
        'schemaVersion': 1,
        'themeMode': 'system',
        'defaultChapterFormat': 'text',
        'editorLineHeight': 1.8,
        'editorFontSize': 15,
        'editorContentWidth': 900,
        'dailyWordGoal': 2000,
        'findMatchCase': false,
        'findUseRegex': false,
        'paragraphSpacing': 6,
      }),
    });
    final loaded = await repository.load();
    expect(loaded, isNotNull);
    expect(loaded!.editorLineHeight, 1.8);
    expect(loaded.paragraphSpacing, 6);
  });

  test(
    'immersive toggles tolerate wrong-typed values by falling back to false',
    () async {
      // 新字段类型不符（如字符串）时回退 false，且不影响其它字段加载。
      SharedPreferences.setMockInitialValues({
        'lore.app.preferences': jsonEncode({
          'schemaVersion': 1,
          'themeMode': 'dark',
          'defaultChapterFormat': 'text',
          'editorLineHeight': 1.95,
          'editorFontSize': 17,
          'editorContentWidth': 900,
          'dailyWordGoal': 2000,
          'findMatchCase': false,
          'findUseRegex': false,
          'typewriterMode': 'true', // 不是 bool
          'focusMode': 1, // 不是 bool
        }),
      });

      final loaded = await repository.load();
      expect(loaded, isNotNull);
      expect(loaded!.themeMode, AppThemeMode.dark);
      expect(loaded.typewriterMode, isFalse);
      expect(loaded.focusMode, isFalse);
    },
  );

  test(
    'editorFontFamily tolerates wrong-typed or unknown values by falling back',
    () async {
      // editorFontFamily 是后加字段：无论值是错类型（int/bool/null）还是未知枚举
      // 字符串，都应静默回落默认值（文楷），且不影响其它字段加载。
      for (final bad in <Object?>[42, true, null, 'comic_sans']) {
        SharedPreferences.setMockInitialValues({
          'lore.app.preferences': jsonEncode({
            'schemaVersion': 1,
            'themeMode': 'system',
            'defaultChapterFormat': 'text',
            'editorLineHeight': 1.5,
            'editorFontSize': 15,
            'editorContentWidth': 900,
            'dailyWordGoal': 2000,
            'findMatchCase': false,
            'findUseRegex': false,
            'editorFontFamily': bad,
          }),
        });
        final loaded = await repository.load();
        expect(loaded, isNotNull, reason: 'bad editorFontFamily=$bad');
        expect(
          loaded!.editorFontFamily,
          AppFontFamily.wenkai,
          reason: 'bad=$bad',
        );
        expect(loaded.editorFontSize, 15, reason: 'bad=$bad');
      }
    },
  );

  test('returns null on corrupted JSON', () async {
    SharedPreferences.setMockInitialValues({'lore.app.preferences': '{bad'});
    expect(await repository.load(), isNull);
  });

  test('returns null on wrong schemaVersion', () async {
    SharedPreferences.setMockInitialValues({
      'lore.app.preferences': jsonEncode({'schemaVersion': 999}),
    });
    expect(await repository.load(), isNull);
  });

  test('returns null when a typed field has the wrong type', () async {
    SharedPreferences.setMockInitialValues({
      'lore.app.preferences': jsonEncode({
        'schemaVersion': 1,
        'themeMode': 'system',
        'defaultChapterFormat': 'markdown',
        'editorLineHeight': 'wide', // not a number
        'editorFontSize': 17,
        'editorContentWidth': 900,
        'dailyWordGoal': 2000,
        'findMatchCase': false,
        'findUseRegex': false,
      }),
    });
    expect(await repository.load(), isNull);
  });

  test('returns null on unknown enum value', () async {
    SharedPreferences.setMockInitialValues({
      'lore.app.preferences': jsonEncode({
        'schemaVersion': 1,
        'themeMode': 'oled', // unknown
        'defaultChapterFormat': 'markdown',
        'editorLineHeight': 1.95,
        'editorFontSize': 17,
        'editorContentWidth': 900,
        'dailyWordGoal': 2000,
        'findMatchCase': false,
        'findUseRegex': false,
      }),
    });
    expect(await repository.load(), isNull);
  });

  test('watch emits latest value after save', () async {
    final first = AppPreferences.defaults();
    final second = first.copyWith(themeMode: AppThemeMode.dark);

    final emitted = <AppThemeMode>[];
    final subscription = repository.watch().listen(
      (preferences) => emitted.add(preferences.themeMode),
    );

    await repository.save(first);
    await repository.save(second);

    expect(emitted, [AppThemeMode.system, AppThemeMode.dark]);

    await subscription.cancel();
  });

  test('round-trips gridLineMode through save and load', () async {
    for (final mode in GridLineMode.values) {
      final original = AppPreferences.defaults().copyWith(gridLineMode: mode);
      await repository.save(original);
      final loaded = await repository.load();
      expect(loaded, isNotNull);
      expect(loaded!.gridLineMode, mode, reason: 'mode=$mode');
    }
  });

  test(
    'loads v2 blob missing gridLineMode as none and bumps schema to v3',
    () async {
      // v2 blob（老用户）没有 gridLineMode 键：应迁移到 v3，网格线回落 none，
      // 既有排版值原样保留（v2→v3 不做值迁移）。
      SharedPreferences.setMockInitialValues({
        'lore.app.preferences': jsonEncode({
          'schemaVersion': 2,
          'themeMode': 'sepia',
          'defaultChapterFormat': 'text',
          'editorLineHeight': 1.8,
          'editorFontSize': 16,
          'editorContentWidth': 900,
          'dailyWordGoal': 1000,
          'findMatchCase': false,
          'findUseRegex': false,
          'typewriterMode': true,
          'focusMode': false,
          'firstLineIndent': true,
          'paragraphSpacing': 20,
          'editorFontFamily': 'serif',
        }),
      });
      final loaded = await repository.load();
      expect(loaded, isNotNull);
      expect(loaded!.schemaVersion, 3);
      expect(loaded.gridLineMode, GridLineMode.none);
      expect(loaded.editorLineHeight, 1.8);
      expect(loaded.paragraphSpacing, 20);
      expect(loaded.editorFontFamily, AppFontFamily.serif);
    },
  );
}
