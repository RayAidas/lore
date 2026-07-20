import 'package:flutter/material.dart';

import 'editor_style.dart';
import 'lore_text_controller.dart';

final class LoreTextEditor extends StatelessWidget {
  const LoreTextEditor({
    required this.controller,
    required this.scrollController,
    this.style = const EditorStyle.defaults(),
    this.autofocus = false,
    this.focusNode,
    super.key,
  });

  final LoreTextController controller;
  final ScrollController scrollController;
  final EditorStyle style;
  final bool autofocus;

  /// 外部聚焦入口：章节标题栏按回车后 requestFocus 此节点可直接聚焦正文字段
  /// （Markdown 编辑器是单个 TextField，无需像大文本编辑器那样转交 block）。
  final FocusNode? focusNode;

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
            child: TextSelectionTheme(
              data: TextSelectionThemeData(
                // 选区手柄与光标同色系，避免"中性光标 + 蓝手柄"的割裂
                // （移动端可见；桌面端鼠标选择不显手柄）。
                selectionHandleColor: EditorCaret.color(
                  Theme.of(context).colorScheme,
                ),
              ),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                scrollController: scrollController,
                autofocus: autofocus,
                expands: true,
                maxLines: null,
                minLines: null,
                keyboardType: TextInputType.multiline,
                textAlignVertical: TextAlignVertical.top,
                cursorColor: EditorCaret.color(Theme.of(context).colorScheme),
                cursorWidth: EditorCaret.width,
                cursorRadius: EditorCaret.radius,
                cursorHeight: EditorCaret.heightFor(style.fontSize),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  height: style.lineHeight,
                  fontSize: style.fontSize,
                  letterSpacing: style.letterSpacing,
                  fontFamily: style.fontFamily,
                  fontFamilyFallback: style.fontFamilyFallback,
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
          ),
        );
      },
    );
  }
}
