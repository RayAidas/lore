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
  static const _schemaVersion = 5;

  /// load 时接受的历史 schema 版本：v1–v4 均就地迁移到当前 v5。
  ///
  /// v1→v2 收紧行高默认（按值匹配替换，保留用户自定义）；v2→v3 仅新增网格线
  /// 字段；v3→v4 仅新增高亮调色板字段（缺失取默认）；v4→v5 段间距由绝对像素
  /// 改为字号倍数（÷字号，保留用户实际看到的比例）。
  static const _legacySchemaVersions = {1, 2, 3, 4};

  /// v1 行高默认值：迁移时识别「仍停留在旧默认」的行高，替换为当前默认。
  static const _v1EditorLineHeight = 1.5;

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
      // 接受 v1–v4（旧版，就地迁移）或 v5（当前）；其它版本号视为损坏。
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
      // 段间距在 v5 起改为字号倍数；老 blob（v1–v4）存的是绝对像素，迁移时
      // 在下方 resolvedParagraphSpacing 除以字号换算。这里先保留原始读取结果
      // 与「是否真的存了该键」的标记。
      final rawParagraphSpacing = value['paragraphSpacing'];
      final paragraphSpacing = rawParagraphSpacing is num
          ? rawParagraphSpacing.toDouble()
          : AppPreferences.defaults().paragraphSpacing;
      // 正文字体是后加字段，老 blob 里可能没有——容错读取，缺失回落默认值。
      final editorFontFamily =
          _fontFamilyFromString(value['editorFontFamily']) ??
          AppPreferences.defaults().editorFontFamily;
      // 网格线模式是 v3 新增字段，v1/v2 blob 里没有——容错读取，缺失回落默认。
      final gridLineMode =
          _gridLineModeFromString(value['gridLineMode']) ??
          AppPreferences.defaults().gridLineMode;
      // 高亮调色板是 v4 新增字段。仅当存在且**全部元素为 int** 时采用,任一
      // 非法(如 1.5、"red"、null)整体回退默认,避免静默写 0(透明黑)。
      final rawPalette = value['highlightPalette'];
      final highlightPalette =
          rawPalette is List && rawPalette.every((e) => e is int)
          ? List<int>.from(rawPalette)
          : AppPreferences.defaults().highlightPalette;
      // v1 → v2 迁移（行高）：仅当行高仍停留在 v1 默认 1.5 时替换为当前默认
      // （视觉瘦身）；用户自定义原样保留。按值匹配使迁移对同一输入幂等，不会
      // 每次冷启动把自定义抹回默认。
      final resolvedLineHeight =
          migratingFromV1 && lineHeight == _v1EditorLineHeight
          ? AppPreferences.defaults().editorLineHeight
          : lineHeight.toDouble();
      // v4 → v5 迁移（段间距）：v4 及更早以绝对像素存储，改为字号倍数——除以
      // 已校验的字号保留用户实际看到的段距比例，夹到滑块范围 [0, 3]。缺键的
      // 老 blob（rawParagraphSpacing 非 num）已回落新默认倍数，不再参与换算。
      final resolvedParagraphSpacing =
          migratingFromLegacy && rawParagraphSpacing is num
          ? (paragraphSpacing / fontSize).clamp(0.0, 3.0).toDouble()
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
