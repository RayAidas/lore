import 'package:flutter/material.dart';

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
      popupMenuTheme: PopupMenuThemeData(
        color: colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
