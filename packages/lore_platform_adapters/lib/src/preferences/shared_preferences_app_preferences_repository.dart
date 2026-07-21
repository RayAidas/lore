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
  static const _schemaVersion = 4;

  /// load 时接受的历史 schema 版本：v1、v2、v3 均就地迁移到当前 v4。
  ///
  /// v1→v2 收紧行高/段间距默认（按值匹配替换，保留用户自定义）；v2→v3 仅新增
  /// 网格线字段；v3→v4 仅新增高亮调色板字段（缺失取默认），不动既有值。
  static const _legacySchemaVersions = {1, 2, 3};

  /// v1 排版默认值：迁移时识别「仍停留在旧默认」的值，仅这些值被替换为 v2 默认。
  static const _v1EditorLineHeight = 1.5;
  static const _v1ParagraphSpacing = 12.0;

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
      if (value is! Map<String, Object?>) {
        return null;
      }
      // 接受 v1/v2（旧版，就地迁移）或 v3（当前）；其它版本号视为损坏。
      final storedVersion = value['schemaVersion'];
      final migratingFromV1 = storedVersion == 1;
      final migratingFromLegacy =
          storedVersion is int && _legacySchemaVersions.contains(storedVersion);
      if (storedVersion is! int ||
          (!migratingFromLegacy && storedVersion != _schemaVersion)) {
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
      // 沉浸写作开关是后加字段，老 blob 里可能没有——容错读取，缺失/类型
      // 不符时取 false，且不纳入上面的严格失败守卫，避免老用户升级丢偏好。
      final typewriterMode = value['typewriterMode'] is bool
          ? value['typewriterMode']! as bool
          : false;
      final focusMode = value['focusMode'] is bool
          ? value['focusMode']! as bool
          : false;
      // 段落排版同理：首行缩进缺失取 true（默认开），段间距缺失取当前默认。
      final firstLineIndent = value['firstLineIndent'] is bool
          ? value['firstLineIndent']! as bool
          : true;
      final paragraphSpacing = value['paragraphSpacing'] is num
          ? (value['paragraphSpacing']! as num).toDouble()
          : AppPreferences.defaults().paragraphSpacing;
      // 正文字体是后加字段，老 blob 里可能没有——容错读取，缺失回落默认值。
      final editorFontFamily =
          _fontFamilyFromString(value['editorFontFamily']) ??
          AppPreferences.defaults().editorFontFamily;
      // 网格线模式是 v3 新增字段，v1/v2 blob 里没有——容错读取，缺失回落默认。
      final gridLineMode =
          _gridLineModeFromString(value['gridLineMode']) ??
          AppPreferences.defaults().gridLineMode;
      // 高亮调色板是 v4 新增字段,v1/v2/v3 blob 里没有——容错读取,缺失回落默认。
      final highlightPalette = value['highlightPalette'] is List
          ? (value['highlightPalette']! as List)
              .map((e) => e is int ? e : 0)
              .toList(growable: false)
          : AppPreferences.defaults().highlightPalette;
      // v1 → v2 迁移：仅当行高/段间距仍停留在 v1 默认时替换为 v2 默认（视觉
      // 瘦身）；用户已自定义的值原样保留。v2 blob 的排版值已是当前默认，无需
      // 迁移。按值匹配使迁移对同一输入幂等，不会每次冷启动把自定义抹回默认。
      final resolvedLineHeight =
          migratingFromV1 && lineHeight == _v1EditorLineHeight
          ? AppPreferences.defaults().editorLineHeight
          : lineHeight.toDouble();
      final resolvedParagraphSpacing =
          migratingFromV1 && paragraphSpacing == _v1ParagraphSpacing
          ? AppPreferences.defaults().paragraphSpacing
          : paragraphSpacing;
      return AppPreferences(
        schemaVersion: _schemaVersion,
        themeMode: themeMode,
        defaultChapterFormat: defaultChapterFormat,
        editorLineHeight: resolvedLineHeight,
        editorFontSize: fontSize.toDouble(),
        editorContentWidth: contentWidth.toDouble(),
        dailyWordGoal: dailyWordGoal,
        findMatchCase: matchCase,
        findUseRegex: useRegex,
        typewriterMode: typewriterMode,
        focusMode: focusMode,
        firstLineIndent: firstLineIndent,
        paragraphSpacing: resolvedParagraphSpacing,
        editorFontFamily: editorFontFamily,
        gridLineMode: gridLineMode,
        highlightPalette: highlightPalette,
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
      'typewriterMode': preferences.typewriterMode,
      'focusMode': preferences.focusMode,
      'firstLineIndent': preferences.firstLineIndent,
      'paragraphSpacing': preferences.paragraphSpacing,
      'editorFontFamily': preferences.editorFontFamily.name,
      'gridLineMode': preferences.gridLineMode.name,
      'highlightPalette': preferences.highlightPalette,
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

  AppFontFamily? _fontFamilyFromString(Object? value) {
    if (value is! String) {
      return null;
    }
    return switch (value) {
      'system' => AppFontFamily.system,
      'wenkai' => AppFontFamily.wenkai,
      'sans' => AppFontFamily.sans,
      'serif' => AppFontFamily.serif,
      'kai' => AppFontFamily.kai,
      _ => null,
    };
  }

  GridLineMode? _gridLineModeFromString(Object? value) {
    if (value is! String) {
      return null;
    }
    return switch (value) {
      'none' => GridLineMode.none,
      'solid' => GridLineMode.solid,
      'dashed' => GridLineMode.dashed,
      _ => null,
    };
  }
}
