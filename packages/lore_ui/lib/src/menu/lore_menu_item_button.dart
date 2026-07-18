import 'package:flutter/material.dart';

final class LoreMenuItemButton extends StatelessWidget {
  const LoreMenuItemButton({
    required this.label,
    required this.onPressed,
    this.destructive = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return MenuItemButton(
      onPressed: onPressed,
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colorScheme.onSurface.withValues(alpha: 0.38);
          }
          return destructive ? colorScheme.error : colorScheme.onSurface;
        }),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return null;
          }
          final foreground = destructive
              ? colorScheme.error
              : colorScheme.onSurface;
          if (states.contains(WidgetState.pressed)) {
            return foreground.withValues(alpha: 0.1);
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return foreground.withValues(alpha: 0.06);
          }
          return null;
        }),
      ),
      child: Text(label),
    );
  }
}
