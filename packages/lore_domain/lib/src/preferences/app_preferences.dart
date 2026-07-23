import '../content/content_types.dart';
import '../highlight/highlight.dart';
import 'keybindings.dart';

/// 用户可配置的应用级外观与编辑器偏好。
///
/// 这些设置跨书库生效，与具体小说无关。小说级的写作、阅读和导出设置
/// 仍由 [NovelMetadata] 等小说级元数据承载。
enum AppThemeMode { system, light, sepia, dark }

/// 应用背景的来源。图片背景在 macOS 与 Android 可用。
enum AppBackgroundMode { theme, image }

/// 编辑器正文字体偏好。
///
/// `system` 走平台默认；其余按字体 family 名解析，宿主缺该字体时自动走
/// fallback 链（由 app 层的字体注册表定义），保证总有合理渲染。
enum AppFontFamily { system, wenkai, sans, serif, kai }

/// 章节正文（TXT）每行下方的网格线模式。
///
/// `none` 不绘制；`solid` 实线；`dashed` 虚线。开启时段落内每行底部画线，
/// 段落之间（空行）的底部即下一段顶部也画线，唯独全文第一段上方不画。
/// 仅 TXT 编辑器消费。
enum GridLineMode { none, solid, dashed }

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
    required this.gridLineMode,
    required this.highlightPalette,
    this.keybindings = Keybindings.defaults,
    this.backgroundMode = AppBackgroundMode.theme,
    this.backgroundImagePaths = const [],
    this.backgroundImagePath,
    this.backgroundOpacity = 0.84,
    this.backgroundImageDimness = 0.2,
  });

  static const schemaVersionCurrent = 8;

  /// 开箱默认：字号 18、行高 1.45、段间距 1.2（字号倍数）；标题→首段留白由
  /// EditorStyle 派生（(段间距 + 1.0) × 字号）保证始终宽于段间距。
  factory AppPreferences.defaults() => const AppPreferences(
    schemaVersion: schemaVersionCurrent,
    themeMode: AppThemeMode.system,
    defaultChapterFormat: ChapterFormat.text,
    editorLineHeight: 1.45,
    editorFontSize: 18,
    editorContentWidth: 900,
    dailyWordGoal: 2000,
    findMatchCase: false,
    findUseRegex: false,
    typewriterMode: false,
    focusMode: false,
    firstLineIndent: true,
    paragraphSpacing: 1.2,
    editorFontFamily: AppFontFamily.wenkai,
    gridLineMode: GridLineMode.none,
    highlightPalette: HighlightPalette.defaults,
    keybindings: Keybindings.defaults,
    backgroundMode: AppBackgroundMode.theme,
    backgroundImagePaths: [],
    backgroundOpacity: 0.84,
    backgroundImageDimness: 0.2,
  );

  final int schemaVersion;
  final AppThemeMode themeMode;

  /// 工作区全局快捷键映射。未在表中的动作在 UI 显示「未设置」，运行时不触发。
  final Keybindings keybindings;

  /// 新建小说时章节的默认文件格式。
  final ChapterFormat defaultChapterFormat;

  /// 编辑器正文排版参数，实时反映到编辑器组件。
  final double editorLineHeight;
  final double editorFontSize;
  final double editorContentWidth;

  /// 编辑器正文字体（作用于 txt 正文与 Markdown 预览）。
  final AppFontFamily editorFontFamily;

  /// 章节正文每行下方的网格线模式（无/实线/虚线）。仅 TXT 编辑器生效。
  final GridLineMode gridLineMode;

  /// 文字高亮调色板:6 个 ARGB 槽位,用户可替换。高亮本身存定格颜色
  /// ([Highlight.colorArgb]),改调色板只影响新建高亮的快捷选色。
  final List<int> highlightPalette;

  /// 背景来源；图片路径由应用复制并管理，不依赖用户原始文件仍然存在。
  final AppBackgroundMode backgroundMode;

  /// 已复制到应用数据目录、可供切换的背景图片。
  final List<String> backgroundImagePaths;

  /// 当前选中的背景图片；应为 [backgroundImagePaths] 中的一项。
  final String? backgroundImagePath;

  /// 背景模式下主要界面表面的不透明度，值域 [0, 1]。
  final double backgroundOpacity;

  /// 图片背景上覆盖的黑色遮罩强度，值域 [0, 1]。
  final double backgroundImageDimness;

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

  /// 段落排版：段落之间的间距（字号倍数，渲染时 × [editorFontSize]）。仅 TXT
  /// 编辑器生效。
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
    GridLineMode? gridLineMode,
    List<int>? highlightPalette,
    Keybindings? keybindings,
    AppBackgroundMode? backgroundMode,
    List<String>? backgroundImagePaths,
    String? backgroundImagePath,
    bool clearBackgroundImagePath = false,
    double? backgroundOpacity,
    double? backgroundImageDimness,
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
      gridLineMode: gridLineMode ?? this.gridLineMode,
      highlightPalette: highlightPalette ?? this.highlightPalette,
      keybindings: keybindings ?? this.keybindings,
      backgroundMode: backgroundMode ?? this.backgroundMode,
      backgroundImagePaths: backgroundImagePaths ?? this.backgroundImagePaths,
      backgroundImagePath: clearBackgroundImagePath
          ? null
          : backgroundImagePath ?? this.backgroundImagePath,
      backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
      backgroundImageDimness:
          backgroundImageDimness ?? this.backgroundImageDimness,
    );
  }
}
