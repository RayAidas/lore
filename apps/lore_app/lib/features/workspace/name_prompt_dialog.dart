import 'package:flutter/material.dart';

/// 通用的「输入名称」对话框：单输入框 + 取消/确认。
final class NamePromptDialog extends StatefulWidget {
  const NamePromptDialog({
    required this.title,
    required this.label,
    required this.initialValue,
    this.suffix,
    super.key,
  });

  final String title;
  final String label;
  final String initialValue;
  final String? suffix;

  @override
  State<NamePromptDialog> createState() => _NamePromptDialogState();
}

final class _NamePromptDialogState extends State<NamePromptDialog> {
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
        autofocus: true,
        decoration: InputDecoration(
          labelText: widget.label,
          suffixText: widget.suffix,
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('确认'),
        ),
      ],
    );
  }
}
