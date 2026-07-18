import 'dart:async';
import 'dart:convert';

import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 基于 [SharedPreferences] 的设备本地应用偏好持久化适配器。
///
/// 命名约定与 [SharedPreferencesWorkspaceSessionRepository] 一致：
/// 单一 JSON 字符串 key（`lore.app.preferences`），内嵌 `schemaVersion`，
/// 解析失败或版本不符时 [load] 返回 `null`，让上层回退到默认值。
final class SharedPreferencesAppPreferencesRepository
    implements AppPreferencesRepository {
  SharedPreferencesAppPreferencesRepository();

  static const _key = 'lore.app.preferences';
  static const _schemaVersion = 1;

  // sync: true 让 save 时的 add 同步派发给监听者，避免异步广播在测试/快速
  // 连续写入下丢失事件（偏好仅在本进程内变更，同步派发安全）。
  final StreamController<AppPreferences> _controller =
      StreamController<AppPreferences>.broadcast(sync: true);

  @override
  Future<AppPreferences?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_key);
    if (encoded == null) {
      return null;
    }
    try {
      final value = jsonDecode(encoded);
      if (value is! Map<String, Object?> ||
          value['schemaVersion'] != _schemaVersion) {
        return null;
      }
      final themeMode = _themeModeFromString(value['themeMode']);
      final defaultChapterFormat = _chapterFormatFromString(
        value['defaultChapterFormat'],
      );
      final lineHeight = value['editorLineHeight'];
      final fontSize = value['editorFontSize'];
      final contentWidth = value['editorContentWidth'];
      final dailyWordGoal = value['dailyWordGoal'];
      final matchCase = value['findMatchCase'];
      final useRegex = value['findUseRegex'];
      if (themeMode == null ||
          defaultChapterFormat == null ||
          lineHeight is! num ||
          fontSize is! num ||
          contentWidth is! num ||
          dailyWordGoal is! int ||
          matchCase is! bool ||
          useRegex is! bool) {
        return null;
      }
      return AppPreferences(
        schemaVersion: _schemaVersion,
        themeMode: themeMode,
        defaultChapterFormat: defaultChapterFormat,
        editorLineHeight: lineHeight.toDouble(),
        editorFontSize: fontSize.toDouble(),
        editorContentWidth: contentWidth.toDouble(),
        dailyWordGoal: dailyWordGoal,
        findMatchCase: matchCase,
        findUseRegex: useRegex,
      );
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> save(AppPreferences preferences) async {
    final store = await SharedPreferences.getInstance();
    await store.setString(_key, jsonEncode(_toJson(preferences)));
    _controller.add(preferences);
  }

  @override
  Stream<AppPreferences> watch() => _controller.stream;

  Map<String, Object?> _toJson(AppPreferences preferences) {
    return {
      'schemaVersion': _schemaVersion,
      'themeMode': preferences.themeMode.name,
      'defaultChapterFormat': preferences.defaultChapterFormat.name,
      'editorLineHeight': preferences.editorLineHeight,
      'editorFontSize': preferences.editorFontSize,
      'editorContentWidth': preferences.editorContentWidth,
      'dailyWordGoal': preferences.dailyWordGoal,
      'findMatchCase': preferences.findMatchCase,
      'findUseRegex': preferences.findUseRegex,
    };
  }

  AppThemeMode? _themeModeFromString(Object? value) {
    if (value is! String) {
      return null;
    }
    return switch (value) {
      'system' => AppThemeMode.system,
      'light' => AppThemeMode.light,
      'sepia' => AppThemeMode.sepia,
      'dark' => AppThemeMode.dark,
      _ => null,
    };
  }

  ChapterFormat? _chapterFormatFromString(Object? value) {
    if (value is! String) {
      return null;
    }
    return switch (value) {
      'text' => ChapterFormat.text,
      'markdown' => ChapterFormat.markdown,
      _ => null,
    };
  }
}
