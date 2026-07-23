import 'package:flutter/material.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_ui/lore_ui.dart';

/// 单个主题选项的展示与渲染数据。
///
/// 设置页的卡片选择器（标签 + 取自 [data] 的迷你预览）与 app 层的主题应用
/// 共用本表，保证「点哪个卡片」与「实际渲染哪个 [ThemeData]」永远一致；
/// 新增主题时只在本文件加一行注册 + 在 lore_ui 加工厂即可。
final class AppThemeOption {
  const AppThemeOption(this.mode, this.label, this.data);

  /// 偏好枚举值，也是持久化的 key。
  final AppThemeMode mode;

  /// 设置页卡片展示的 2 字意境名。
  final String label;

  /// 该主题对应的 [ThemeData]；卡片预览也直接取它的 colorScheme，所见即所得。
  final ThemeData data;

  /// 是否为亮色基调（决定卡片预览的文字是否需要深色）。
  bool get isLight => data.colorScheme.brightness == Brightness.light;
}

/// 主题注册表：[AppThemeMode] → 展示名 + [ThemeData]。
///
/// 顺序即设置页卡片展示顺序（亮色在前、暗色在后）。调用 [options] 会构造
/// 6 份 [ThemeData]；设置页与 app 各自每帧至多取一次，开销可忽略，换来
/// 「新增主题只改一处」的单点维护。
abstract final class AppThemeOptions {
  const AppThemeOptions._();

  /// 所有具名主题（不含「跟随系统」——它是模式而非主题，由卡片选择器单独
  /// 渲染分屏预览）。
  static List<AppThemeOption> get options => <AppThemeOption>[
    AppThemeOption(AppThemeMode.light, '素白', LoreTheme.light()),
    AppThemeOption(AppThemeMode.sepia, '纸张', LoreTheme.sepia()),
    AppThemeOption(AppThemeMode.frost, '霜华', LoreTheme.frost()),
    AppThemeOption(AppThemeMode.green, '翠微', LoreTheme.green()),
    AppThemeOption(AppThemeMode.dark, '夜间', LoreTheme.dark()),
    AppThemeOption(AppThemeMode.ink, '墨渊', LoreTheme.ink()),
  ];

  /// 取某模式对应的 [ThemeData]。
  ///
  /// 用穷举 switch 而非遍历 [options]：app 路径只构造 1 份（而非 6 份），
  /// 且枚举新增值却漏注册时为**编译期错误**，不会静默退化成素白。
  static ThemeData dataFor(AppThemeMode mode) => switch (mode) {
    AppThemeMode.system => LoreTheme.light(),
    AppThemeMode.light => LoreTheme.light(),
    AppThemeMode.sepia => LoreTheme.sepia(),
    AppThemeMode.frost => LoreTheme.frost(),
    AppThemeMode.green => LoreTheme.green(),
    AppThemeMode.dark => LoreTheme.dark(),
    AppThemeMode.ink => LoreTheme.ink(),
  };

  /// 解析某主题模式应用到 [MaterialApp] 所需的三元组。
  ///
  /// [AppThemeMode.system] 走真·系统跟随（light / dark 双方案）；其余显式模式
  /// 把 theme 与 darkTheme 都指向所选主题，themeMode 取其亮度——确保「选哪个
  /// 就显示哪个」，尤其第二个暗色主题（墨渊）不会被硬编码的 [LoreTheme.dark]
  /// 退化成夜间。提出为纯函数以便单测锁定该回归。
  static ({ThemeData theme, ThemeData darkTheme, ThemeMode themeMode})
  resolveAppliedTheme(AppThemeMode mode) {
    if (mode == AppThemeMode.system) {
      return (
        theme: LoreTheme.light(),
        darkTheme: LoreTheme.dark(),
        themeMode: ThemeMode.system,
      );
    }
    final data = dataFor(mode);
    return (
      theme: data,
      darkTheme: data,
      themeMode: data.colorScheme.brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
    );
  }
}
