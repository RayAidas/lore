/// 编辑器正文的行为与排版参数。
///
/// 由上层从应用偏好派生并注入编辑器组件，使字号、行高、行宽与字距能在
/// 用户调整后实时反映，并承载沉浸写作开关（打字机/专注模式）。[defaults]
/// 对齐编辑器历史硬编码值，保证无偏好时视觉与行为零回归。
final class EditorStyle {
  const EditorStyle({
    required this.lineHeight,
    required this.fontSize,
    required this.contentWidth,
    required this.letterSpacing,
    this.typewriterMode = false,
    this.focusMode = false,
  });

  const EditorStyle.defaults()
    : lineHeight = 1.95,
      fontSize = 17,
      contentWidth = 900,
      letterSpacing = 0.2,
      typewriterMode = false,
      focusMode = false;

  final double lineHeight;
  final double fontSize;
  final double contentWidth;
  final double letterSpacing;

  /// 打字机模式：键入/移动光标时把光标行滚动到视口垂直居中（仅 TXT 编辑器消费）。
  final bool typewriterMode;

  /// 专注模式：淡化非当前段落（仅 TXT 编辑器消费）。
  final bool focusMode;

  EditorStyle copyWith({
    double? lineHeight,
    double? fontSize,
    double? contentWidth,
    double? letterSpacing,
    bool? typewriterMode,
    bool? focusMode,
  }) {
    return EditorStyle(
      lineHeight: lineHeight ?? this.lineHeight,
      fontSize: fontSize ?? this.fontSize,
      contentWidth: contentWidth ?? this.contentWidth,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      typewriterMode: typewriterMode ?? this.typewriterMode,
      focusMode: focusMode ?? this.focusMode,
    );
  }
}
