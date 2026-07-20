import 'package:lore_domain/lore_domain.dart';

/// 单个字体选项的展示与解析数据。
///
/// [fontFamily] 为 null 表示走 Flutter / 主题默认；否则按 family 名解析，
/// 宿主缺该字体时按 [fontFamilyFallback] 顺序回退（CJK 跨平台必备）。
class FontOption {
  const FontOption({
    required this.label,
    this.fontFamily,
    this.fontFamilyFallback,
  });

  /// 设置页与下拉项展示用的人话名称。
  final String label;

  /// 传给 [TextStyle.fontFamily] 的 family 名（null = 系统默认）。
  final String? fontFamily;

  /// 传给 [TextStyle.fontFamilyFallback] 的回退链。
  final List<String>? fontFamilyFallback;
}

/// 编辑器正文字体注册表：把 [AppFontFamily] 偏好映射到具体的 family 名与
/// fallback 链。设置页（标签 + 实时预览）与文档面板（解析 family 名）共用本表，
/// 保证选择与渲染一致。
///
/// family 名依据：本机 CoreText 枚举确认 macOS 上 PingFang SC / Songti SC /
/// Kaiti SC / STKaiti / STSong / Heiti SC / Hiragino Sans GB 等均存在；文楷
/// （LXGWWenKai）已内置、跨平台一致。Android 上 Noto Sans CJK SC 通常存在
/// （苹方降级为它），宋体 / 楷体在 Android 可能降级为系统默认——已知平台差异。
abstract final class AppFontOptions {
  const AppFontOptions._();

  static const options = <AppFontFamily, FontOption>{
    AppFontFamily.system: FontOption(label: '系统默认'),
    AppFontFamily.wenkai: FontOption(
      label: '霞鹜文楷',
      fontFamily: 'LXGWWenKai',
      fontFamilyFallback: ['Kaiti SC', 'STKaiti', 'BiauKaiTC', 'Kai'],
    ),
    AppFontFamily.sans: FontOption(
      label: '苹方',
      fontFamily: 'PingFang SC',
      fontFamilyFallback: [
        'Heiti SC',
        'Hiragino Sans GB',
        'Noto Sans CJK SC',
        'Microsoft YaHei',
        'Source Han Sans SC',
      ],
    ),
    AppFontFamily.serif: FontOption(
      label: '宋体',
      fontFamily: 'Songti SC',
      fontFamilyFallback: [
        'STSong',
        'Hiragino Mincho ProN',
        'Source Han Serif SC',
        'Noto Serif CJK SC',
        'SimSun',
      ],
    ),
    AppFontFamily.kai: FontOption(
      label: '楷体',
      fontFamily: 'Kaiti SC',
      fontFamilyFallback: ['STKaiti', 'BiauKaiTC', 'Kai'],
    ),
  };

  /// 解析偏好为具体选项；未知值回落到文楷（默认体验）。
  static FontOption resolve(AppFontFamily family) =>
      options[family] ?? options[AppFontFamily.wenkai]!;
}
