import '../content/content_types.dart';

/// 用户可配置的应用级外观与编辑器偏好。
///
/// 这些设置跨书库生效，与具体小说无关。小说级的写作、阅读和导出设置
/// 仍由 [NovelMetadata] 等小说级元数据承载。
enum AppThemeMode { system, light, sepia, dark }

/// 编辑器正文字体偏好。
///
/// `system` 走平台默认；其余按字体 family 名解析，宿主缺该字体时自动走
/// fallback 链（由 app 层的字体注册表定义），保证总有合理渲染。
enum AppFontFamily { system, wenkai, sans, serif, kai }

final class AppPreferences {
  const AppPreferences({
    required this.schemaVersion,
    required this.themeMode,
    required this.defaultChapterFormat,
    required this.editorLineHeight,
    required this.editorFontSize,
    required this.editorContentWidth,
    required this.dailyWordGoal,
    required this.findMatchCase,
    required this.findUseRegex,
    required this.typewriterMode,
    required this.focusMode,
    required this.firstLineIndent,
    required this.paragraphSpacing,
    required this.editorFontFamily,
  });

  static const schemaVersionCurrent = 1;

  /// 默认值对齐当前硬编码体验，确保无偏好记录时视觉与行为零回归。
  factory AppPreferences.defaults() => const AppPreferences(
    schemaVersion: schemaVersionCurrent,
    themeMode: AppThemeMode.system,
    defaultChapterFormat: ChapterFormat.text,
    editorLineHeight: 1.5,
    editorFontSize: 15,
    editorContentWidth: 900,
    dailyWordGoal: 2000,
    findMatchCase: false,
    findUseRegex: false,
    typewriterMode: false,
    focusMode: false,
    firstLineIndent: true,
    paragraphSpacing: 12,
    editorFontFamily: AppFontFamily.wenkai,
  );

  final int schemaVersion;
  final AppThemeMode themeMode;

  /// 新建小说时章节的默认文件格式。
  final ChapterFormat defaultChapterFormat;

  /// 编辑器正文排版参数，实时反映到编辑器组件。
  final double editorLineHeight;
  final double editorFontSize;
  final double editorContentWidth;

  /// 编辑器正文字体（作用于 txt 正文与 Markdown 预览）。
  final AppFontFamily editorFontFamily;

  /// 每日写作字数目标，0 表示禁用。
  final int dailyWordGoal;

  /// 查找替换的默认选项。
  final bool findMatchCase;
  final bool findUseRegex;

  /// 沉浸写作：打字机模式（光标行保持垂直居中）。仅 TXT 编辑器生效。
  final bool typewriterMode;

  /// 沉浸写作：专注模式（淡化非当前段落）。仅 TXT 编辑器生效。
  final bool focusMode;

  /// 段落排版：新建段落时在段首自动插入两个全角空格（首行缩进 2 字）。
  /// 仅 TXT 编辑器生效。
  final bool firstLineIndent;

  /// 段落排版：段落之间的额外间距（逻辑像素）。仅 TXT 编辑器生效。
  final double paragraphSpacing;

  AppPreferences copyWith({
    AppThemeMode? themeMode,
    ChapterFormat? defaultChapterFormat,
    double? editorLineHeight,
    double? editorFontSize,
    double? editorContentWidth,
    int? dailyWordGoal,
    bool? findMatchCase,
    bool? findUseRegex,
    bool? typewriterMode,
    bool? focusMode,
    bool? firstLineIndent,
    double? paragraphSpacing,
    AppFontFamily? editorFontFamily,
  }) {
    return AppPreferences(
      schemaVersion: schemaVersion,
      themeMode: themeMode ?? this.themeMode,
      defaultChapterFormat: defaultChapterFormat ?? this.defaultChapterFormat,
      editorLineHeight: editorLineHeight ?? this.editorLineHeight,
      editorFontSize: editorFontSize ?? this.editorFontSize,
      editorContentWidth: editorContentWidth ?? this.editorContentWidth,
      dailyWordGoal: dailyWordGoal ?? this.dailyWordGoal,
      findMatchCase: findMatchCase ?? this.findMatchCase,
      findUseRegex: findUseRegex ?? this.findUseRegex,
      typewriterMode: typewriterMode ?? this.typewriterMode,
      focusMode: focusMode ?? this.focusMode,
      firstLineIndent: firstLineIndent ?? this.firstLineIndent,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      editorFontFamily: editorFontFamily ?? this.editorFontFamily,
    );
  }
}
