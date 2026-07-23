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
  static const _schemaVersion = 9;

  /// load 时接受的历史 schema 版本：v1–v8 均就地迁移到当前 v9。
  ///
  /// v1→v2 收紧行高默认（按值匹配替换，保留用户自定义）；v2→v3 仅新增网格线
  /// 字段；v3→v4 仅新增高亮调色板字段（缺失取默认）；v4→v5 段间距由绝对像素
  /// 改为字号倍数（÷字号，保留用户实际看到的比例）；v7→v8 新增快捷键映射
  /// 字段（缺失整体取默认，未知动作名前向兼容跳过）；v8→v9 修正回车键码
  /// （0x0d → 真实 enter 0x10000000d，否则显示空白且不触发）。
  static const _legacySchemaVersions = {1, 2, 3, 4, 5, 6, 7, 8};
  static const _pixelParagraphSpacingSchemaVersions = {1, 2, 3, 4};

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
      // 接受 v1–v8（旧版，就地迁移）或 v9（当前）；其它版本号视为损坏。
      final storedVersion = value['schemaVersion'];
      final migratingFromV1 = storedVersion == 1;
      final migratingFromLegacy =
          storedVersion is int && _legacySchemaVersions.contains(storedVersion);
      final migratingPixelParagraphSpacing =
          storedVersion is int &&
          _pixelParagraphSpacingSchemaVersions.contains(storedVersion);
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
      // v7 把单图升级为图库。v6 单图自动进入列表；旧透明窗口设置已撤回，
      // 迁移时回到主题色。
      final backgroundMode = value['backgroundMode'] == 'transparent'
          ? AppBackgroundMode.theme
          : _backgroundModeFromString(value['backgroundMode']) ??
                AppPreferences.defaults().backgroundMode;
      final backgroundImagePath = value['backgroundImagePath'] is String
          ? value['backgroundImagePath']! as String
          : null;
      final rawBackgroundImagePaths = value['backgroundImagePaths'];
      final backgroundImagePaths =
          rawBackgroundImagePaths is List &&
              rawBackgroundImagePaths.every((item) => item is String)
          ? List<String>.from(rawBackgroundImagePaths)
          : backgroundImagePath == null
          ? <String>[]
          : <String>[backgroundImagePath];
      final selectedBackgroundImagePath =
          backgroundImagePath != null &&
              backgroundImagePaths.contains(backgroundImagePath)
          ? backgroundImagePath
          : backgroundImagePaths.isEmpty
          ? null
          : backgroundImagePaths.first;
      final backgroundOpacity = value['backgroundOpacity'] is num
          ? (value['backgroundOpacity']! as num)
                .toDouble()
                .clamp(0.15, 1.0)
                .toDouble()
          : AppPreferences.defaults().backgroundOpacity;
      final backgroundImageDimness = value['backgroundImageDimness'] is num
          ? (value['backgroundImageDimness']! as num)
                .toDouble()
                .clamp(0.0, 0.8)
                .toDouble()
          : AppPreferences.defaults().backgroundImageDimness;
      // 快捷键映射是 v8 新增字段。v7 及更早的 blob 里没有——缺失整体取默认；
      // 存在则逐条解析：未知动作名（前向兼容）与损坏组合（留作未设置）跳过。
      final rawKeybindings = _keybindingsFromJson(value['keybindings']);
      // v8 及更早的默认把回车存成原始码点 0x0d（≠ 真实 enter 键 0x10000000d），
      // 既显示空白也匹配不上按键事件——legacy 迁移时改写为真实 enter 键码。
      final keybindings = migratingFromLegacy
          ? _normalizeEnterKey(rawKeybindings)
          : rawKeybindings;
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
          migratingPixelParagraphSpacing && rawParagraphSpacing is num
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
        keybindings: keybindings,
        backgroundMode: backgroundMode,
        backgroundImagePaths: backgroundImagePaths,
        backgroundImagePath: selectedBackgroundImagePath,
        backgroundOpacity: backgroundOpacity,
        backgroundImageDimness: backgroundImageDimness,
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
      'keybindings': _keybindingsToJson(preferences.keybindings),
      'backgroundMode': preferences.backgroundMode.name,
      'backgroundImagePaths': preferences.backgroundImagePaths,
      'backgroundImagePath': preferences.backgroundImagePath,
      'backgroundOpacity': preferences.backgroundOpacity,
      'backgroundImageDimness': preferences.backgroundImageDimness,
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
      'frost' => AppThemeMode.frost,
      'green' => AppThemeMode.green,
      'ink' => AppThemeMode.ink,
      _ => null,
    };
  }

  AppBackgroundMode? _backgroundModeFromString(Object? value) {
    if (value is! String) {
      return null;
    }
    return switch (value) {
      'theme' => AppBackgroundMode.theme,
      'image' => AppBackgroundMode.image,
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

  Map<String, Object?> _keybindingsToJson(Keybindings keybindings) {
    final result = <String, Object?>{};
    for (final entry in keybindings.bindings.entries) {
      result[entry.key.name] = _keyCombinationToJson(entry.value);
    }
    return result;
  }

  Map<String, Object> _keyCombinationToJson(KeyCombination combo) => {
    'key': combo.logicalKeyId,
    'meta': combo.meta,
    'control': combo.control,
    'alt': combo.alt,
    'shift': combo.shift,
  };

  Keybindings _keybindingsFromJson(Object? value) {
    if (value is! Map<String, Object?>) {
      // v7 及更早的 blob 无此字段 → 整体取默认。
      return Keybindings.defaults;
    }
    final result = <ShortcutAction, KeyCombination>{};
    value.forEach((name, raw) {
      final action = _shortcutActionFromName(name);
      if (action == null) {
        return; // 未知动作名：前向兼容跳过（新版写入、旧版读取互不崩溃）。
      }
      final combo = _keyCombinationFromJson(raw);
      if (combo == null) {
        return; // 损坏的组合：留作未设置，由用户重新绑定。
      }
      result[action] = combo;
    });
    return Keybindings(result);
  }

  ShortcutAction? _shortcutActionFromName(String name) {
    for (final action in ShortcutAction.values) {
      if (action.name == name) {
        return action;
      }
    }
    return null;
  }

  KeyCombination? _keyCombinationFromJson(Object? value) {
    if (value is! Map<String, Object?>) {
      return null;
    }
    final key = value['key'];
    if (key is! int) {
      return null;
    }
    return KeyCombination(
      logicalKeyId: key,
      meta: value['meta'] is bool ? value['meta']! as bool : false,
      control: value['control'] is bool ? value['control']! as bool : false,
      alt: value['alt'] is bool ? value['alt']! as bool : false,
      shift: value['shift'] is bool ? value['shift']! as bool : false,
    );
  }

  /// 把映射里所有原始回车码点（0x0d）改写为真实 enter 键码（0x10000000d）。
  /// v8 默认误用 0x0d，导致显示空白且运行时匹配不上回车事件。
  Keybindings _normalizeEnterKey(Keybindings keybindings) {
    var changed = false;
    final next = <ShortcutAction, KeyCombination>{};
    for (final entry in keybindings.bindings.entries) {
      final combo = entry.value;
      if (combo.logicalKeyId == 0x0d) {
        next[entry.key] = KeyCombination(
          logicalKeyId: 0x10000000d,
          meta: combo.meta,
          control: combo.control,
          alt: combo.alt,
          shift: combo.shift,
        );
        changed = true;
      } else {
        next[entry.key] = combo;
      }
    }
    return changed ? Keybindings(next) : keybindings;
  }
}
