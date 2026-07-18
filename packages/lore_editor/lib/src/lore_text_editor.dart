import 'package:flutter/material.dart';

import 'editor_style.dart';
import 'lore_text_controller.dart';

final class LoreTextEditor extends StatelessWidget {
  const LoreTextEditor({
    required this.controller,
    required this.scrollController,
    this.style = const EditorStyle.defaults(),
    this.autofocus = false,
    super.key,
  });

  final LoreTextController controller;
  final ScrollController scrollController;
  final EditorStyle style;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth > style.contentWidth
            ? style.contentWidth
            : constraints.maxWidth;
        return Center(
          child: SizedBox(
            width: width,
            height: constraints.maxHeight,
            child: TextField(
              controller: controller,
              scrollController: scrollController,
              autofocus: autofocus,
              expands: true,
              maxLines: null,
              minLines: null,
              keyboardType: TextInputType.multiline,
              textAlignVertical: TextAlignVertical.top,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                height: style.lineHeight,
                fontSize: style.fontSize,
                letterSpacing: style.letterSpacing,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 52,
                  vertical: 42,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
