import 'package:flutter/material.dart';

import 'lore_dialog_styles.dart';

final class LoreTextPromptDialog extends StatefulWidget {
  const LoreTextPromptDialog({
    required this.title,
    required this.label,
    this.initialValue = '',
    this.suffixText,
    this.helperText,
    this.keyboardType,
    this.obscureText = false,
    this.cancelLabel = '取消',
    this.confirmLabel = '确认',
    this.autofocus = true,
    super.key,
  });

  final String title;
  final String label;
  final String initialValue;
  final String? suffixText;
  final String? helperText;
  final TextInputType? keyboardType;

  /// 是否遮蔽输入（API Key 等敏感字段）。
  final bool obscureText;

  final String cancelLabel;
  final String confirmLabel;
  final bool autofocus;

  @override
  State<LoreTextPromptDialog> createState() => _LoreTextPromptDialogState();
}

final class _LoreTextPromptDialogState extends State<LoreTextPromptDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      content: TextField(
        controller: _controller,
        autofocus: widget.autofocus,
        keyboardType: widget.keyboardType,
        obscureText: widget.obscureText,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: widget.label,
          suffixText: widget.suffixText,
          helperText: widget.helperText,
        ),
        onSubmitted: _submit,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: loreDialogSecondaryButton(colorScheme),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          onPressed: () => _submit(_controller.text),
          style: loreDialogPrimaryButton(colorScheme),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }

  void _submit(String value) {
    Navigator.of(context).pop(value);
  }
}

Future<String?> showLoreTextPromptDialog({
  required BuildContext context,
  required String title,
  required String label,
  String initialValue = '',
  String? suffixText,
  String? helperText,
  TextInputType? keyboardType,
  bool obscureText = false,
  String cancelLabel = '取消',
  String confirmLabel = '确认',
  bool autofocus = true,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => LoreTextPromptDialog(
      title: title,
      label: label,
      initialValue: initialValue,
      suffixText: suffixText,
      helperText: helperText,
      keyboardType: keyboardType,
      obscureText: obscureText,
      cancelLabel: cancelLabel,
      confirmLabel: confirmLabel,
      autofocus: autofocus,
    ),
  );
}
