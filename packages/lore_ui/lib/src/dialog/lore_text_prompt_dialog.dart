import 'package:flutter/material.dart';

final class LoreTextPromptDialog extends StatefulWidget {
  const LoreTextPromptDialog({
    required this.title,
    required this.label,
    this.initialValue = '',
    this.suffixText,
    this.helperText,
    this.keyboardType,
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
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: widget.autofocus,
        keyboardType: widget.keyboardType,
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
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          onPressed: () => _submit(_controller.text),
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
      cancelLabel: cancelLabel,
      confirmLabel: confirmLabel,
      autofocus: autofocus,
    ),
  );
}
