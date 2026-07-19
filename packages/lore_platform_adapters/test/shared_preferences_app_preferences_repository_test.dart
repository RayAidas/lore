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
  });

  test('loads legacy blob missing immersive toggles with other prefs intact', () async {
    // 模拟 1.x 版本写入的旧 blob：没有 typewriterMode/focusMode 键。
    // 应当加载成功，旧字段保留，新字段回退默认 false，而非整体回退默认值。
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
    expect(loaded.paragraphSpacing, 18);
  });

  test('immersive toggles tolerate wrong-typed values by falling back to false', () async {
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
  });

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
}
