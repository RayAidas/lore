import 'package:flutter/material.dart';

import 'lore_text_controller.dart';

final class LoreTextEditor extends StatelessWidget {
  const LoreTextEditor({
    required this.controller,
    required this.scrollController,
    this.autofocus = false,
    super.key,
  });

  final LoreTextController controller;
  final ScrollController scrollController;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      scrollController: scrollController,
      autofocus: autofocus,
      expands: true,
      maxLines: null,
      minLines: null,
      keyboardType: TextInputType.multiline,
      textAlignVertical: TextAlignVertical.top,
      style: Theme.of(
        context,
      ).textTheme.bodyLarge?.copyWith(height: 1.8, fontSize: 17),
      decoration: const InputDecoration(
        border: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(horizontal: 48, vertical: 32),
      ),
    );
  }
}
