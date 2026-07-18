/// 编辑器正文的排版参数。
///
/// 由上层从应用偏好派生并注入 [LoreTextEditor]，使字号、行高、
/// 行宽与字距能在用户调整后实时反映。[defaults] 对齐编辑器历史硬编码值，
/// 保证无偏好时视觉零回归。
final class EditorStyle {
  const EditorStyle({
    required this.lineHeight,
    required this.fontSize,
    required this.contentWidth,
    required this.letterSpacing,
  });

  const EditorStyle.defaults()
    : lineHeight = 1.95,
      fontSize = 17,
      contentWidth = 900,
      letterSpacing = 0.2;

  final double lineHeight;
  final double fontSize;
  final double contentWidth;
  final double letterSpacing;

  EditorStyle copyWith({
    double? lineHeight,
    double? fontSize,
    double? contentWidth,
    double? letterSpacing,
  }) {
    return EditorStyle(
      lineHeight: lineHeight ?? this.lineHeight,
      fontSize: fontSize ?? this.fontSize,
      contentWidth: contentWidth ?? this.contentWidth,
      letterSpacing: letterSpacing ?? this.letterSpacing,
    );
  }
}
