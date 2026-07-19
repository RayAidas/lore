import 'package:flutter/material.dart';

import 'lore_dialog_styles.dart';

/// 要求用户精确输入 [expectedText] 才能确认的危险操作对话框。
///
/// 用于破坏性极高、误触代价大的操作（如删除整本小说）。确认按钮只有在
/// 输入文本（忽略首尾空白）等于 [expectedText] 时才会启用，从根本上避免
/// 误删。
final class LoreTypeToConfirmDialog extends StatefulWidget {
  const LoreTypeToConfirmDialog({
    required this.title,
    required this.message,
    required this.expectedText,
    this.helperText,
    this.cancelLabel = '取消',
    this.confirmLabel = '删除',
    this.destructive = true,
    super.key,
  });

  final String title;
  final String message;
  final String expectedText;
  final String? helperText;
  final String cancelLabel;
  final String confirmLabel;
  final bool destructive;

  @override
  State<LoreTypeToConfirmDialog> createState() =>
      _LoreTypeToConfirmDialogState();
}

final class _LoreTypeToConfirmDialogState
    extends State<LoreTypeToConfirmDialog> {
  late final TextEditingController _controller;
  bool _isMatched = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) {
      return;
    }
    final matched = _controller.text.trim() == widget.expectedText;
    if (matched != _isMatched) {
      setState(() => _isMatched = matched);
    }
  }

  void _confirm() {
    if (_isMatched) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(helperText: widget.helperText),
            onSubmitted: (_) => _confirm(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: loreDialogSecondaryButton(colorScheme),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          onPressed: _isMatched ? _confirm : null,
          style: loreDialogPrimaryButton(
            colorScheme,
            destructive: widget.destructive,
          ),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

Future<bool> showLoreTypeToConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String expectedText,
  String? helperText,
  String cancelLabel = '取消',
  String confirmLabel = '删除',
  bool destructive = true,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => LoreTypeToConfirmDialog(
      title: title,
      message: message,
      expectedText: expectedText,
      helperText: helperText,
      cancelLabel: cancelLabel,
      confirmLabel: confirmLabel,
      destructive: destructive,
    ),
  );
  return confirmed ?? false;
}
