import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_ui/lore_ui.dart';

void main() {
  final themes = <String, ThemeData>{
    'light': LoreTheme.light(),
    'sepia': LoreTheme.sepia(),
    'dark': LoreTheme.dark(),
  };

  for (final entry in themes.entries) {
    test('${entry.key} theme uses the touch menu visual baseline', () {
      final theme = entry.value;
      final popupShape = theme.popupMenuTheme.shape as RoundedRectangleBorder;
      final menuStyle = theme.menuTheme.style!;
      final menuShape = menuStyle.shape!.resolve(<WidgetState>{});
      final menuItemStyle = theme.menuButtonTheme.style!;

      expect(
        theme.popupMenuTheme.menuPadding,
        const EdgeInsets.symmetric(vertical: 5),
      );
      expect(theme.popupMenuTheme.elevation, 6);
      expect(theme.popupMenuTheme.position, PopupMenuPosition.under);
      expect(popupShape.borderRadius, BorderRadius.circular(8));
      expect(popupShape.side.color, theme.colorScheme.outlineVariant);
      expect(
        menuStyle.padding!.resolve(<WidgetState>{}),
        const EdgeInsets.symmetric(vertical: 5),
      );
      expect(menuStyle.elevation!.resolve(<WidgetState>{}), 6);
      expect(
        (menuShape as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(8),
      );
      expect(
        menuItemStyle.minimumSize!.resolve(<WidgetState>{}),
        const Size(0, 48),
      );
      expect(menuItemStyle.tapTargetSize, MaterialTapTargetSize.padded);
      expect(menuItemStyle.visualDensity, VisualDensity.standard);
      expect(
        (menuItemStyle.shape!.resolve(<WidgetState>{})
                as RoundedRectangleBorder)
            .borderRadius,
        BorderRadius.circular(5),
      );
    });

    test('${entry.key} theme makes disabled menu labels secondary', () {
      final theme = entry.value;
      final labelStyle = theme.popupMenuTheme.labelTextStyle!;
      final enabled = labelStyle.resolve(<WidgetState>{})!;
      final disabled = labelStyle.resolve(<WidgetState>{WidgetState.disabled})!;

      expect(enabled.fontSize, 13.5);
      expect(enabled.fontWeight, FontWeight.w500);
      expect(enabled.color, theme.colorScheme.onSurface);
      expect(disabled.color, isNot(enabled.color));
    });

    test('${entry.key} theme uses the modern dialog visual baseline', () {
      final theme = entry.value;
      final dialogTheme = theme.dialogTheme;
      final shape = dialogTheme.shape as RoundedRectangleBorder;

      expect(
        dialogTheme.backgroundColor,
        theme.colorScheme.surfaceContainerLowest,
      );
      expect(dialogTheme.surfaceTintColor, Colors.transparent);
      expect(dialogTheme.elevation, 8);
      expect(
        dialogTheme.constraints,
        const BoxConstraints(minWidth: 320, maxWidth: 400),
      );
      expect(dialogTheme.insetPadding, const EdgeInsets.all(24));
      expect(
        dialogTheme.actionsPadding,
        const EdgeInsets.fromLTRB(16, 12, 16, 16),
      );
      expect(shape.borderRadius, BorderRadius.circular(10));
      expect(dialogTheme.titleTextStyle?.fontSize, 17);
      expect(dialogTheme.titleTextStyle?.fontWeight, FontWeight.w700);
      expect(dialogTheme.contentTextStyle?.height, 1.55);
    });
  }

  test('macOS theme uses the compact menu visual baseline', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final menuItemStyle = LoreTheme.light().menuButtonTheme.style!;

      expect(
        menuItemStyle.minimumSize!.resolve(<WidgetState>{}),
        const Size(0, 34),
      );
      expect(menuItemStyle.tapTargetSize, MaterialTapTargetSize.shrinkWrap);
      expect(menuItemStyle.visualDensity, VisualDensity.standard);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('surface opacity keeps foreground colors opaque', () {
    final base = LoreTheme.light();
    final translucent = LoreTheme.withSurfaceOpacity(base, 0.65);

    expect(translucent.colorScheme.surface.a, closeTo(0.65, 0.001));
    expect(
      translucent.colorScheme.surfaceContainerLowest.a,
      closeTo(0.65, 0.001),
    );
    expect(translucent.scaffoldBackgroundColor.a, closeTo(0.65, 0.001));
    expect(translucent.dividerColor.a, closeTo(0.65, 0.001));
    expect(translucent.colorScheme.outlineVariant.a, closeTo(0.65, 0.001));
    expect(
      (translucent.appBarTheme.shape! as Border).bottom.color.a,
      closeTo(0.65, 0.001),
    );
    expect(translucent.colorScheme.onSurface.a, 1);
    expect(translucent.colorScheme.primary.a, 1);
  });
}
