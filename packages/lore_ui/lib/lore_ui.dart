import 'package:flutter/material.dart';

abstract final class LoreTheme {
  static ThemeData light() {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF665A4D)),
      useMaterial3: true,
    );
  }

  static ThemeData dark() {
    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        brightness: Brightness.dark,
        seedColor: const Color(0xFFB7A58E),
      ),
      useMaterial3: true,
    );
  }
}
