import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_ui/lore_ui.dart';

void main() {
  testWidgets('menu item button is text-only and invokes its callback', (
    tester,
  ) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: LoreTheme.light(),
        home: Scaffold(
          body: LoreMenuItemButton(
            label: '重命名',
            onPressed: () => pressed = true,
          ),
        ),
      ),
    );

    final menuItem = tester.widget<MenuItemButton>(find.byType(MenuItemButton));
    expect(menuItem.leadingIcon, isNull);
    expect(tester.getSize(find.byType(MenuItemButton)).height, 48);

    await tester.tap(find.text('重命名'));
    await tester.pump();
    expect(pressed, isTrue);
  });

  testWidgets('destructive and disabled menu states use semantic colors', (
    tester,
  ) async {
    final theme = LoreTheme.light();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: LoreMenuItemButton(
            label: '永久删除',
            onPressed: null,
            destructive: true,
          ),
        ),
      ),
    );

    final menuItem = tester.widget<MenuItemButton>(find.byType(MenuItemButton));
    expect(
      menuItem.style?.foregroundColor?.resolve(<WidgetState>{}),
      theme.colorScheme.error,
    );
    expect(
      menuItem.style?.foregroundColor?.resolve(<WidgetState>{
        WidgetState.disabled,
      }),
      theme.colorScheme.onSurface.withValues(alpha: 0.38),
    );
  });

  testWidgets('popup menu item returns its generic value', (tester) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: LoreTheme.light(),
        home: Scaffold(
          body: PopupMenuButton<String>(
            onSelected: (value) => selected = value,
            itemBuilder: (context) => [
              LorePopupMenuItem(value: 'rename', label: '重命名'),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    final popupItem = find.byWidgetPredicate(
      (widget) => widget is LorePopupMenuItem<String>,
    );
    expect(tester.getSize(popupItem).height, 48);
    expect(
      find.descendant(of: popupItem, matching: find.byType(Icon)),
      findsNothing,
    );

    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    expect(selected, 'rename');
  });

  testWidgets('macOS menu items use the compact desktop height', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final popupItem = LorePopupMenuItem(value: 'rename', label: '重命名');

      await tester.pumpWidget(
        MaterialApp(
          theme: LoreTheme.light(),
          home: const Scaffold(
            body: LoreMenuItemButton(label: '重命名', onPressed: null),
          ),
        ),
      );

      expect(tester.getSize(find.byType(MenuItemButton)).height, 34);
      expect(popupItem.height, 34);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
