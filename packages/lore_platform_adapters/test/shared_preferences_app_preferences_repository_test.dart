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
      paragraphSpacing: 1.5,
      editorFontFamily: AppFontFamily.serif,
      backgroundMode: AppBackgroundMode.image,
      backgroundImagePaths: const [
        '/managed/background-1.jpg',
        '/managed/background-2.jpg',
      ],
      backgroundImagePath: '/managed/background-2.jpg',
      backgroundOpacity: 0.72,
      backgroundImageDimness: 0.35,
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
    expect(loaded.paragraphSpacing, 1.5);
    expect(loaded.editorFontFamily, AppFontFamily.serif);
    expect(loaded.backgroundMode, AppBackgroundMode.image);
    expect(loaded.backgroundImagePaths, [
      '/managed/background-1.jpg',
      '/managed/background-2.jpg',
    ]);
    expect(loaded.backgroundImagePath, '/managed/background-2.jpg');
    expect(loaded.backgroundOpacity, 0.72);
    expect(loaded.backgroundImageDimness, 0.35);
  });

  test(
    'loads legacy blob missing immersive toggles with other prefs intact',
    () async {
      // 模拟 1.x 版本写入的旧 blob：没有 typewriterMode/focusMode 键。
      // 应当加载成功：沉浸开关回退默认 false；行高 2.2 是自定义值（≠ v1 默认
      // 1.5）故保留；段间距缺失 → 回落当前默认倍数（不参与 ÷字号换算）；其余
      // 偏好不变。
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
      // 行高 2.2 是自定义值（≠ v1 默认）→ 保留；段间距缺失 → 回落当前默认倍数。
      expect(loaded.editorLineHeight, 2.2);
      expect(
        loaded.paragraphSpacing,
        AppPreferences.defaults().paragraphSpacing,
      );
      // editorFontFamily 是后加字段，旧 blob 缺该键应回落默认值（文楷）。
      expect(loaded.editorFontFamily, AppFontFamily.wenkai);
    },
  );

  test(
    'v1 blob migrates lineHeight default and converts paragraph spacing px to multiplier',
    () async {
      // 行高仍停留在 v1 默认 1.5 → 替换为当前默认；段间距 12px @字号15 → ÷字号
      // = 0.8 倍数（保留用户看到的段距比例）；其余偏好不变。
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
      // 12px @ 字号 15 → 0.8 倍数（保留用户看到的段距比例）。
      expect(loaded.paragraphSpacing, 0.8);
      expect(loaded.editorFontSize, 15);
      expect(loaded.themeMode, AppThemeMode.system);
    },
  );

  test(
    'v1 blob keeps custom lineHeight and converts custom paragraph spacing ratio',
    () async {
      // 行高 1.8 自定义（≠ v1 默认 1.5）→ 保留；段间距 6px @字号15 → ÷字号
      // = 0.4 倍数（保留用户看到的段距比例）。
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
      expect(loaded.paragraphSpacing, 0.4);
    },
  );

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
    'loads v2 blob missing gridLineMode as none and migrates to current schema',
    () async {
      // v2 blob（老用户）没有 gridLineMode 键：应迁移到当前版本，网格线回落
      // none；段间距 20px @字号16 → ÷字号 = 1.25 倍数（v4→v5 换算）。
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
      expect(loaded!.schemaVersion, 9);
      expect(loaded.gridLineMode, GridLineMode.none);
      expect(loaded.editorLineHeight, 1.8);
      expect(loaded.paragraphSpacing, 1.25);
      expect(loaded.editorFontFamily, AppFontFamily.serif);
    },
  );

  test(
    'loads v3 blob missing highlightPalette as defaults and migrates to current schema',
    () async {
      // v3 blob(老用户)没有 highlightPalette:迁移到当前版本,调色板回落默认,
      // 既有值(gridLineMode 等)原样保留。
      SharedPreferences.setMockInitialValues({
        'lore.app.preferences': jsonEncode({
          'schemaVersion': 3,
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
          'gridLineMode': 'dashed',
        }),
      });
      final loaded = await repository.load();
      expect(loaded, isNotNull);
      expect(loaded!.schemaVersion, 9);
      expect(loaded.highlightPalette, HighlightPalette.defaults);
      expect(loaded.gridLineMode, GridLineMode.dashed);
    },
  );

  test(
    'paragraph spacing migration is idempotent across save and reload',
    () async {
      // 迁移只在 legacy blob 上发生一次：load v4(px)→迁移为倍数→save(v7)→再 load
      // 时 migratingFromLegacy=false，倍数不再被除以字号。若有人误把守卫改宽，
      // 第二次 load 会把 0.8 再除成 ~0.053，此测试立即变红。
      SharedPreferences.setMockInitialValues({
        'lore.app.preferences': jsonEncode({
          'schemaVersion': 4,
          'themeMode': 'system',
          'defaultChapterFormat': 'text',
          'editorLineHeight': 1.45,
          'editorFontSize': 15,
          'editorContentWidth': 900,
          'dailyWordGoal': 2000,
          'findMatchCase': false,
          'findUseRegex': false,
          'typewriterMode': false,
          'focusMode': false,
          'firstLineIndent': true,
          'paragraphSpacing': 12,
          'editorFontFamily': 'wenkai',
          'gridLineMode': 'none',
        }),
      });
      final first = await repository.load();
      expect(first, isNotNull);
      expect(first!.paragraphSpacing, 0.8); // 12px @ 字号 15

      await repository.save(first);
      final reloaded = await repository.load();
      expect(reloaded, isNotNull);
      expect(reloaded!.schemaVersion, 9);
      // 仍是 0.8，没有被二次除以字号。
      expect(reloaded.paragraphSpacing, 0.8);
    },
  );

  test('v5 multiplier and missing background fields migrate to v7', () async {
    SharedPreferences.setMockInitialValues({
      'lore.app.preferences': jsonEncode({
        'schemaVersion': 5,
        'themeMode': 'dark',
        'defaultChapterFormat': 'text',
        'editorLineHeight': 1.45,
        'editorFontSize': 18,
        'editorContentWidth': 900,
        'dailyWordGoal': 2000,
        'findMatchCase': false,
        'findUseRegex': false,
        'paragraphSpacing': 1.2,
      }),
    });

    final loaded = await repository.load();

    expect(loaded, isNotNull);
    expect(loaded!.schemaVersion, 9);
    expect(loaded.paragraphSpacing, 1.2);
    expect(loaded.backgroundMode, AppBackgroundMode.theme);
    expect(loaded.backgroundImagePath, isNull);
    expect(loaded.backgroundImagePaths, isEmpty);
  });

  test('v6 single image migrates into the background gallery', () async {
    SharedPreferences.setMockInitialValues({
      'lore.app.preferences': jsonEncode({
        'schemaVersion': 6,
        'themeMode': 'light',
        'defaultChapterFormat': 'text',
        'editorLineHeight': 1.45,
        'editorFontSize': 18,
        'editorContentWidth': 900,
        'dailyWordGoal': 2000,
        'findMatchCase': false,
        'findUseRegex': false,
        'backgroundMode': 'image',
        'backgroundImagePath': '/managed/legacy.jpg',
      }),
    });

    final loaded = await repository.load();

    expect(loaded, isNotNull);
    expect(loaded!.schemaVersion, 9);
    expect(loaded.backgroundMode, AppBackgroundMode.image);
    expect(loaded.backgroundImagePaths, ['/managed/legacy.jpg']);
    expect(loaded.backgroundImagePath, '/managed/legacy.jpg');
  });

  test('v6 transparent mode is retired to the theme background', () async {
    SharedPreferences.setMockInitialValues({
      'lore.app.preferences': jsonEncode({
        'schemaVersion': 6,
        'themeMode': 'light',
        'defaultChapterFormat': 'text',
        'editorLineHeight': 1.45,
        'editorFontSize': 18,
        'editorContentWidth': 900,
        'dailyWordGoal': 2000,
        'findMatchCase': false,
        'findUseRegex': false,
        'backgroundMode': 'transparent',
      }),
    });

    final loaded = await repository.load();

    expect(loaded, isNotNull);
    expect(loaded!.backgroundMode, AppBackgroundMode.theme);
  });

  test(
    'legacy paragraph spacing exceeding the slider max is clamped on migration',
    () async {
      // 老blob 段间距 40px(旧最大值)@字号12 → 40/12 ≈ 3.33,超出滑块上界 3.0
      // → 夹到 3.0,避免迁移后得到一个滑块够不着的超大倍数。
      SharedPreferences.setMockInitialValues({
        'lore.app.preferences': jsonEncode({
          'schemaVersion': 4,
          'themeMode': 'system',
          'defaultChapterFormat': 'text',
          'editorLineHeight': 1.45,
          'editorFontSize': 12,
          'editorContentWidth': 900,
          'dailyWordGoal': 2000,
          'findMatchCase': false,
          'findUseRegex': false,
          'typewriterMode': false,
          'focusMode': false,
          'firstLineIndent': true,
          'paragraphSpacing': 40,
          'editorFontFamily': 'wenkai',
          'gridLineMode': 'none',
        }),
      });
      final loaded = await repository.load();
      expect(loaded, isNotNull);
      expect(loaded!.paragraphSpacing, 3.0);
    },
  );

  test(
    'falls back to defaults on malformed highlightPalette entries',
    () async {
      // 任一非 int(1.5 / "red" / null)→ 整体回退默认,避免静默写 0(透明黑)。
      SharedPreferences.setMockInitialValues({
        'lore.app.preferences': jsonEncode({
          'schemaVersion': 4,
          'themeMode': 'system',
          'defaultChapterFormat': 'text',
          'editorLineHeight': 1.45,
          'editorFontSize': 15,
          'editorContentWidth': 900,
          'dailyWordGoal': 2000,
          'findMatchCase': false,
          'findUseRegex': false,
          'typewriterMode': false,
          'focusMode': false,
          'firstLineIndent': true,
          'paragraphSpacing': 14,
          'editorFontFamily': 'wenkai',
          'gridLineMode': 'none',
          'highlightPalette': [1.5, 'red', null, 0xFFFFD54F],
        }),
      });
      final loaded = await repository.load();
      expect(loaded, isNotNull);
      expect(loaded!.highlightPalette, HighlightPalette.defaults);
    },
  );

  test('round-trips custom keybindings through save and load', () async {
    final original = AppPreferences.defaults().copyWith(
      keybindings: Keybindings.defaults.withBinding(
        ShortcutAction.save,
        const KeyCombination(logicalKeyId: 0x51, meta: true), // keyQ
      ),
    );
    await repository.save(original);
    final loaded = await repository.load();
    expect(loaded, isNotNull);
    expect(
      loaded!.keybindings.bindings[ShortcutAction.save],
      const KeyCombination(logicalKeyId: 0x51, meta: true),
    );
    // 未改动的动作保持默认。
    expect(
      loaded.keybindings.bindings[ShortcutAction.find],
      Keybindings.defaults.bindings[ShortcutAction.find],
    );
  });

  test('round-trips an unbound action as unset', () async {
    final original = AppPreferences.defaults().copyWith(
      keybindings: Keybindings.defaults.withoutBinding(ShortcutAction.save),
    );
    await repository.save(original);
    final loaded = await repository.load();
    expect(loaded, isNotNull);
    expect(
      loaded!.keybindings.bindings.containsKey(ShortcutAction.save),
      isFalse,
    );
  });

  test(
    'loads v7 blob missing keybindings as defaults and migrates to current schema',
    () async {
      // v7 blob（升级前）没有 keybindings 字段：迁移到当前版本，快捷键整体回落
      // 默认（与改造前硬编码一致），其余偏好原样保留。
      SharedPreferences.setMockInitialValues({
        'lore.app.preferences': jsonEncode({
          'schemaVersion': 7,
          'themeMode': 'sepia',
          'defaultChapterFormat': 'text',
          'editorLineHeight': 1.8,
          'editorFontSize': 16,
          'editorContentWidth': 900,
          'dailyWordGoal': 1000,
          'findMatchCase': false,
          'findUseRegex': false,
          'paragraphSpacing': 1.2,
          'editorFontFamily': 'serif',
          'gridLineMode': 'dashed',
          'highlightPalette': HighlightPalette.defaults,
          'backgroundMode': 'theme',
        }),
      });
      final loaded = await repository.load();
      expect(loaded, isNotNull);
      expect(loaded!.schemaVersion, 9);
      expect(loaded.keybindings.bindings, Keybindings.defaults.bindings);
      expect(loaded.editorFontFamily, AppFontFamily.serif);
    },
  );

  test('v8 blob normalizes raw enter key code to the real enter key', () async {
    // v8 默认把回车存成原始码点 0x0d（≠ 真实 enter 0x10000000d）：迁移到 v9 时
    // 改写，否则全屏快捷键显示空白且运行时匹配不上回车事件。
    SharedPreferences.setMockInitialValues({
      'lore.app.preferences': jsonEncode({
        'schemaVersion': 8,
        'themeMode': 'system',
        'defaultChapterFormat': 'text',
        'editorLineHeight': 1.45,
        'editorFontSize': 18,
        'editorContentWidth': 900,
        'dailyWordGoal': 2000,
        'findMatchCase': false,
        'findUseRegex': false,
        'keybindings': {
          'toggleFullscreen': {'key': 13, 'meta': true, 'shift': true},
        },
      }),
    });
    final loaded = await repository.load();
    expect(loaded, isNotNull);
    expect(loaded!.schemaVersion, 9);
    expect(
      loaded.keybindings.bindings[ShortcutAction.toggleFullscreen],
      const KeyCombination(logicalKeyId: 0x10000000d, meta: true, shift: true),
    );
  });

  test(
    'keybindings tolerate unknown action names and malformed combos',
    () async {
      // 前向兼容：未知动作名 'exportPdf' 跳过；find 组合缺 key 视为损坏 → 留作
      // 未设置；save 组合合法 → 保留。结果只含合法且已知的那一条。
      SharedPreferences.setMockInitialValues({
        'lore.app.preferences': jsonEncode({
          'schemaVersion': 8,
          'themeMode': 'system',
          'defaultChapterFormat': 'text',
          'editorLineHeight': 1.45,
          'editorFontSize': 18,
          'editorContentWidth': 900,
          'dailyWordGoal': 2000,
          'findMatchCase': false,
          'findUseRegex': false,
          'keybindings': {
            'save': {'key': 0x51, 'meta': true},
            'find': {'meta': true}, // 缺 key → 损坏
            'exportPdf': {'key': 0x50, 'meta': true}, // 未知动作
          },
        }),
      });
      final loaded = await repository.load();
      expect(loaded, isNotNull);
      expect(
        loaded!.keybindings.bindings[ShortcutAction.save],
        const KeyCombination(logicalKeyId: 0x51, meta: true),
      );
      expect(
        loaded.keybindings.bindings.containsKey(ShortcutAction.find),
        isFalse,
      );
      expect(loaded.keybindings.bindings, hasLength(1));
    },
  );
}
