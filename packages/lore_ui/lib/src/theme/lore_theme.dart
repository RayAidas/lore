import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../menu/lore_menu_metrics.dart';

abstract final class LoreTheme {
  /// 让承载应用界面的中性表面半透明，同时保留前景文字和强调色的不透明度。
  /// 图片背景模式由 app 层启用此变体。
  static ThemeData withSurfaceOpacity(ThemeData theme, double opacity) {
    final resolvedOpacity = opacity.clamp(0.15, 1.0).toDouble();
    if (resolvedOpacity == 1) {
      return theme;
    }
    Color translucent(Color color) => color.withValues(alpha: resolvedOpacity);
    OutlineInputBorder outlineBorder(
      InputBorder? border,
      BorderSide borderSide,
    ) {
      if (border is OutlineInputBorder) {
        return border.copyWith(borderSide: borderSide);
      }
      return OutlineInputBorder(borderSide: borderSide);
    }

    final colorScheme = theme.colorScheme.copyWith(
      surface: translucent(theme.colorScheme.surface),
      surfaceContainerLowest: translucent(
        theme.colorScheme.surfaceContainerLowest,
      ),
      surfaceContainerLow: translucent(theme.colorScheme.surfaceContainerLow),
      surfaceContainer: translucent(theme.colorScheme.surfaceContainer),
      surfaceContainerHigh: translucent(theme.colorScheme.surfaceContainerHigh),
      surfaceContainerHighest: translucent(
        theme.colorScheme.surfaceContainerHighest,
      ),
      outline: translucent(theme.colorScheme.outline),
      outlineVariant: translucent(theme.colorScheme.outlineVariant),
    );
    final outlineSide = BorderSide(color: colorScheme.outlineVariant);
    return theme.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      canvasColor: colorScheme.surface,
      dividerColor: colorScheme.outlineVariant,
      appBarTheme: theme.appBarTheme.copyWith(
        backgroundColor: colorScheme.surfaceContainerLowest,
        shape: Border(bottom: outlineSide),
      ),
      dividerTheme: theme.dividerTheme.copyWith(
        color: colorScheme.outlineVariant,
      ),
      dialogTheme: theme.dialogTheme.copyWith(
        backgroundColor: colorScheme.surfaceContainerLowest,
      ),
      popupMenuTheme: theme.popupMenuTheme.copyWith(
        color: colorScheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: outlineSide,
        ),
      ),
      menuTheme: MenuThemeData(
        style: theme.menuTheme.style?.copyWith(
          backgroundColor: WidgetStatePropertyAll(
            colorScheme.surfaceContainerLowest,
          ),
          side: WidgetStatePropertyAll(outlineSide),
        ),
      ),
      drawerTheme: theme.drawerTheme.copyWith(
        backgroundColor: colorScheme.surface,
      ),
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        fillColor: colorScheme.surfaceContainerLow,
        border: outlineBorder(theme.inputDecorationTheme.border, outlineSide),
        enabledBorder: outlineBorder(
          theme.inputDecorationTheme.enabledBorder,
          outlineSide,
        ),
        focusedBorder: outlineBorder(
          theme.inputDecorationTheme.focusedBorder,
          BorderSide(color: colorScheme.primary, width: 1.5),
        ),
      ),
      tabBarTheme: theme.tabBarTheme.copyWith(
        dividerColor: colorScheme.outlineVariant,
      ),
    );
  }

  static ThemeData light() {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF5D87B8),
          brightness: Brightness.light,
        ).copyWith(
          surface: const Color(0xFFFCFBF9),
          surfaceContainerLowest: const Color(0xFFFFFFFF),
          surfaceContainerLow: const Color(0xFFF7F6F3),
          surfaceContainer: const Color(0xFFF1F0ED),
          outlineVariant: const Color(0xFFE7E5E1),
        );
    return _build(colorScheme);
  }

  /// 纸张/护眼主题：暖米黄底，适合长时间写作。
  ///
  /// 由于 [MaterialApp.themeMode] 仅支持 system/light/dark 三态，
  /// 调用方需在 sepia 时把 `theme:` 直接指向本返回值，并把
  /// `themeMode` 设为 [ThemeMode.light]。
  static ThemeData sepia() {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xFFA87C4C),
          brightness: Brightness.light,
        ).copyWith(
          surface: const Color(0xFFF5EDD9),
          surfaceContainerLowest: const Color(0xFFFBF4E2),
          surfaceContainerLow: const Color(0xFFEFE3C7),
          surfaceContainer: const Color(0xFFE8D9B5),
          outlineVariant: const Color(0xFFD6C39A),
        );
    return _build(colorScheme);
  }

  static ThemeData dark() {
    final colorScheme =
        ColorScheme.fromSeed(
          brightness: Brightness.dark,
          seedColor: const Color(0xFF8FB4DD),
        ).copyWith(
          surface: const Color(0xFF191A1C),
          surfaceContainerLowest: const Color(0xFF151618),
          surfaceContainerLow: const Color(0xFF202124),
          surfaceContainer: const Color(0xFF27282C),
          outlineVariant: const Color(0xFF34363B),
        );
    return _build(colorScheme);
  }

  static ThemeData _build(ColorScheme colorScheme) {
    final platform = defaultTargetPlatform;
    return ThemeData(
      brightness: colorScheme.brightness,
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: colorScheme.surface,
      dividerColor: colorScheme.outlineVariant,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surfaceContainerLowest,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      iconTheme: IconThemeData(color: colorScheme.onSurfaceVariant, size: 20),
      listTileTheme: ListTileThemeData(
        iconColor: colorScheme.onSurfaceVariant,
        selectedColor: colorScheme.onSurface,
        selectedTileColor: colorScheme.primaryContainer.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        minTileHeight: 38,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shadowColor: colorScheme.shadow.withValues(alpha: 0.16),
        elevation: 8,
        barrierColor: Colors.black.withValues(
          alpha: colorScheme.brightness == Brightness.dark ? 0.58 : 0.38,
        ),
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        constraints: const BoxConstraints(minWidth: 320, maxWidth: 400),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.1,
          height: 1.3,
        ),
        contentTextStyle: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 13.5,
          height: 1.55,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shadowColor: colorScheme.shadow.withValues(alpha: 0.16),
        elevation: 6,
        menuPadding: const EdgeInsets.symmetric(vertical: 5),
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            color: states.contains(WidgetState.disabled)
                ? colorScheme.onSurface.withValues(alpha: 0.38)
                : colorScheme.onSurface,
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
          );
        }),
        iconColor: colorScheme.onSurfaceVariant,
        iconSize: 19,
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(
            colorScheme.surfaceContainerLowest,
          ),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shadowColor: WidgetStatePropertyAll(
            colorScheme.shadow.withValues(alpha: 0.16),
          ),
          elevation: const WidgetStatePropertyAll(6),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 5),
          ),
          side: WidgetStatePropertyAll(
            BorderSide(color: colorScheme.outlineVariant),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
      menuButtonTheme: MenuButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(
            Size(0, LoreMenuMetrics.itemHeight(platform)),
          ),
          tapTargetSize: LoreMenuMetrics.tapTargetSize(platform),
          visualDensity: VisualDensity.standard,
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 14),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
          ),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return colorScheme.onSurface.withValues(alpha: 0.09);
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return colorScheme.onSurface.withValues(alpha: 0.055);
            }
            return null;
          }),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        indicatorColor: colorScheme.primary,
        dividerColor: colorScheme.outlineVariant,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
      ),
      tooltipTheme: TooltipThemeData(
        // 反色但使用主题主 token（onSurface / surface）：在 light / dark / sepia
        // 下均自动协调，比默认 inverseSurface 更贴合 Lore 的暖色调。
        decoration: BoxDecoration(
          color: colorScheme.onSurface,
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        textStyle: TextStyle(
          color: colorScheme.surface,
          fontSize: 12,
          height: 1.2,
          fontWeight: FontWeight.w500,
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(5),
        radius: const Radius.circular(8),
        thumbColor: WidgetStatePropertyAll(
          colorScheme.outline.withValues(alpha: 0.45),
        ),
      ),
    );
  }
}

/// 语义色扩展：success / warning 不在 Material [ColorScheme] 标准槽位中，
/// 这里按亮度（亮色含 sepia / 暗色）给出对比度达标的颜色，供 toast 等组件
/// 随主题自动协调，而非硬编码。
extension LoreSemanticColors on ColorScheme {
  /// 成功语义前景色：亮色主题（含 sepia）用深绿，暗色用亮绿以保证对比度。
  Color get successForeground => brightness == Brightness.dark
      ? const Color(0xFF6FBF8E)
      : const Color(0xFF2E7D5B);

  /// 警告语义前景色：亮色主题（含 sepia）用琥珀，暗色用亮琥珀。
  Color get warningForeground => brightness == Brightness.dark
      ? const Color(0xFFE0A04A)
      : const Color(0xFFB26500);
}
