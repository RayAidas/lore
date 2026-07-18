import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../menu/lore_menu_metrics.dart';

abstract final class LoreTheme {
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
        shadowColor: colorScheme.shadow.withValues(alpha: 0.2),
        elevation: 12,
        barrierColor: Colors.black.withValues(
          alpha: colorScheme.brightness == Brightness.dark ? 0.58 : 0.38,
        ),
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        constraints: const BoxConstraints(minWidth: 340, maxWidth: 440),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
        contentTextStyle: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 14,
          height: 1.5,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shadowColor: colorScheme.shadow.withValues(alpha: 0.16),
        elevation: 6,
        menuPadding: const EdgeInsets.symmetric(vertical: 5),
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
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
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
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
