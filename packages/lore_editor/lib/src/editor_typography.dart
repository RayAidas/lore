import 'package:flutter/material.dart';

import 'editor_style.dart';

/// 编辑器正文 / 标题排版与内容宽度布局的单一来源。
///
/// 把「如何从 [EditorStyle] 派生实际 [TextStyle] 与布局框」集中在此，供编辑器
/// （`LoreLargeTextEditor` 块、`ChapterTitleBar`）、历史 diff 视图等所有文本表面
/// 共用——杜绝各表面各自手写派生导致的视觉漂移。改一处、所有表面同变。
abstract final class EditorTypography {
  const EditorTypography._();

  /// 正文样式：`bodyLarge` 为基底，覆写 [EditorStyle] 的行高 / 字号 / 字距 / 字体。
  /// 与 `LoreLargeTextEditor` 块内 textStyle 派生同口径（颜色继承自 `bodyLarge`，
  /// 与编辑器一致，不另设 onSurface）。`bodyLarge` 不可用时为 null（宿主回退到
  /// `DefaultTextStyle`）。
  static TextStyle? bodyText(EditorStyle style, ThemeData theme) {
    return theme.textTheme.bodyLarge?.copyWith(
      height: style.lineHeight,
      fontSize: style.fontSize,
      letterSpacing: style.letterSpacing,
      fontFamily: style.fontFamily,
      fontFamilyFallback: style.fontFamilyFallback,
    );
  }

  /// 标题样式：`titleLarge` 为基底，覆写标题字号（= [EditorStyle.fontSize] ×
  /// [EditorStyle.titleScale]）/ 字重 / 行高 / 字距 / 字体 / 颜色（onSurface）。
  /// 与 `ChapterTitleBar` 同口径；`titleLarge` 不可用时回退到仅含标题字属性的
  /// `TextStyle`，保证非空。
  static TextStyle titleText(EditorStyle style, ThemeData theme) {
    return theme.textTheme.titleLarge?.copyWith(
          fontSize: style.titleFontSize,
          fontWeight: style.titleFontWeight,
          height: style.titleLineHeight,
          letterSpacing: style.letterSpacing,
          fontFamily: style.fontFamily,
          fontFamilyFallback: style.fontFamilyFallback,
          color: theme.colorScheme.onSurface,
        ) ??
        TextStyle(
          fontSize: style.titleFontSize,
          fontWeight: style.titleFontWeight,
          fontFamily: style.fontFamily,
          fontFamilyFallback: style.fontFamilyFallback,
          color: theme.colorScheme.onSurface,
        );
  }

  /// 内容宽度居中框：`Align(topCenter)` + `ConstrainedBox(maxWidth: contentWidth)`。
  /// 窄视口（宽 < contentWidth）时随父约束收窄。编辑器标题栏、正文、diff 共用，
  /// 保证各表面左缘对齐且不溢出父约束。
  static Widget contentFrame(EditorStyle style, {required Widget child}) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: style.contentWidth),
        child: child,
      ),
    );
  }

  /// 阅读框横向内边距：编辑器标题栏与正文在 contentWidth 列内的统一左右留白。
  static const double readingInset = 52;

  /// 标题块上方留白（与 `ChapterTitleBar` 顶部 42 一致）。
  static const double titleTopInset = 42;
}
