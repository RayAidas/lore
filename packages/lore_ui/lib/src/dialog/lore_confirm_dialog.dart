import 'package:flutter/material.dart';

import 'lore_dialog_styles.dart';

final class LoreConfirmDialog extends StatelessWidget {
  const LoreConfirmDialog({
    required this.title,
    required this.message,
    this.cancelLabel = '取消',
    this.confirmLabel = '确认',
    this.confirmEnabled = true,
    this.destructive = false,
    super.key,
  });

  final String title;
  final String message;
  final String cancelLabel;
  final String confirmLabel;
  final bool confirmEnabled;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(title),
      content: Text(message),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: loreDialogSecondaryButton(colorScheme),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: confirmEnabled
              ? () => Navigator.of(context).pop(true)
              : null,
          style: loreDialogPrimaryButton(colorScheme, destructive: destructive),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}

Future<bool> showLoreConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String cancelLabel = '取消',
  String confirmLabel = '确认',
  bool confirmEnabled = true,
  bool destructive = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => LoreConfirmDialog(
      title: title,
      message: message,
      cancelLabel: cancelLabel,
      confirmLabel: confirmLabel,
      confirmEnabled: confirmEnabled,
      destructive: destructive,
    ),
  );
  return confirmed ?? false;
}
