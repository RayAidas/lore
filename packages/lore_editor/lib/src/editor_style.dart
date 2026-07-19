import 'package:flutter/material.dart';

/// 编辑器光标（caret）样式。
///
/// 取代 Material 默认的饱和 primary 蓝色锐角竖条：改用与正文同色系的中性
/// 细条、端部微圆，跟随 light/dark/sepia 主题自适应，在暖纸与极简主题下
/// 更协调、不抢眼。
abstract final class EditorCaret {
  const EditorCaret._();

  static const double width = 1.6;

  static const Radius radius = Radius.circular(1.0);

  /// 光标高度随字号缩放，但与行距解耦：行高会让 Material 默认光标贯穿整个
  /// 行盒显得过高；1.2× 字号约等于字身高度加少量边距，光标贴合文字、不再
  /// 撑满整行。用户调整行高时光标保持稳定。
  static const double heightFactor = 1.2;

  static double heightFor(double fontSize) => fontSize * heightFactor;

  static Color color(ColorScheme colorScheme) {
    return colorScheme.onSurface.withValues(alpha: 0.82);
  }
}

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
    this.firstLineIndent = true,
    this.paragraphSpacing = 18,
    this.titleScale = 1.3,
    this.titleFontWeight = FontWeight.w700,
    this.titleLineHeight = 1.2,
    this.titleBottomSpacing = 12,
  });

  const EditorStyle.defaults()
    : lineHeight = 1.5,
      fontSize = 15,
      contentWidth = 900,
      letterSpacing = 0.2,
      typewriterMode = false,
      focusMode = false,
      firstLineIndent = true,
      paragraphSpacing = 12,
      titleScale = 1.3,
      titleFontWeight = FontWeight.w700,
      titleLineHeight = 1.2,
      titleBottomSpacing = 12;

  final double lineHeight;
  final double fontSize;
  final double contentWidth;
  final double letterSpacing;

  /// 打字机模式：键入/移动光标时把光标行滚动到视口垂直居中（仅 TXT 编辑器消费）。
  final bool typewriterMode;

  /// 专注模式：淡化非当前段落（仅 TXT 编辑器消费）。
  final bool focusMode;

  /// 段落首行缩进：新建段落时在段首自动插入两个全角空格（仅 TXT 编辑器消费）。
  final bool firstLineIndent;

  /// 段落之间的额外间距（逻辑像素，仅 TXT 编辑器消费）。
  final double paragraphSpacing;

  /// 章节标题字号相对 [fontSize] 的倍数（仅章节标题栏消费）。
  final double titleScale;

  /// 章节标题字重（仅章节标题栏消费）。
  final FontWeight titleFontWeight;

  /// 章节标题行高（仅章节标题栏消费，通常比正文略紧）。
  final double titleLineHeight;

  /// 章节标题与正文之间的间距（逻辑像素，仅章节标题栏消费）。
  final double titleBottomSpacing;

  /// 章节标题字号 = [fontSize] × [titleScale]。
  double get titleFontSize => fontSize * titleScale;

  EditorStyle copyWith({
    double? lineHeight,
    double? fontSize,
    double? contentWidth,
    double? letterSpacing,
    bool? typewriterMode,
    bool? focusMode,
    bool? firstLineIndent,
    double? paragraphSpacing,
    double? titleScale,
    FontWeight? titleFontWeight,
    double? titleLineHeight,
    double? titleBottomSpacing,
  }) {
    return EditorStyle(
      lineHeight: lineHeight ?? this.lineHeight,
      fontSize: fontSize ?? this.fontSize,
      contentWidth: contentWidth ?? this.contentWidth,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      typewriterMode: typewriterMode ?? this.typewriterMode,
      focusMode: focusMode ?? this.focusMode,
      firstLineIndent: firstLineIndent ?? this.firstLineIndent,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      titleScale: titleScale ?? this.titleScale,
      titleFontWeight: titleFontWeight ?? this.titleFontWeight,
      titleLineHeight: titleLineHeight ?? this.titleLineHeight,
      titleBottomSpacing: titleBottomSpacing ?? this.titleBottomSpacing,
    );
  }
}
