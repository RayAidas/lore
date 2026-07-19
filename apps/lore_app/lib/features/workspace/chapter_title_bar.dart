import 'package:flutter/material.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_editor/lore_editor.dart';

/// 章节标题栏：左对齐、加粗、字号略大于正文的标题行。
///
/// 形如 `第3章 甜蜜的家`：`第N章` 为**只读锁定前缀**（源自章节编号，单独
/// 渲染为 [Text]，不在可编辑区域内），副标题 `甜蜜的家` 由用户在无框
/// [TextField] 中编辑。两者共用 [EditorStyle] 派生的标题样式。副标题变化经
/// [onChanged] 上报，由工作区置脏并安排自动保存；落盘与文件名联动时再由
/// [ChapterTitleText] 重组为 `第N章 副标题`。
///
/// 仅用于已识别为章节标题的文档（`OpenDocument.chapterNumber != null`）。
final class ChapterTitleBar extends StatefulWidget {
  const ChapterTitleBar({
    required this.chapterNumber,
    required this.subtitle,
    required this.style,
    required this.onChanged,
    this.autofocusSubtitle = false,
    this.onEnter,
    super.key,
  });

  final int chapterNumber;
  final String subtitle;
  final EditorStyle style;
  final ValueChanged<String> onChanged;
  final bool autofocusSubtitle;

  /// 在副标题按回车时触发（用于把焦点交给正文，光标置于正文开头）。
  final VoidCallback? onEnter;

  @override
  State<ChapterTitleBar> createState() => _ChapterTitleBarState();
}

final class _ChapterTitleBarState extends State<ChapterTitleBar> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.subtitle);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant ChapterTitleBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 仅在副标题字段未持有主焦点（用户未正在编辑）时，把外部 subtitle 同步回
    // 控制器；用 hasPrimaryFocus 而非 hasFocus，与正文编辑器的焦点守卫语义一致。
    if (widget.subtitle != _controller.text && !_focusNode.hasPrimaryFocus) {
      _syncing = true;
      _controller.value = TextEditingValue(
        text: widget.subtitle,
        selection: TextSelection.collapsed(offset: widget.subtitle.length),
      );
      _syncing = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final titleStyle =
        theme.textTheme.titleLarge?.copyWith(
          fontSize: widget.style.titleFontSize,
          fontWeight: widget.style.titleFontWeight,
          height: widget.style.titleLineHeight,
          letterSpacing: widget.style.letterSpacing,
          color: colorScheme.onSurface,
        ) ??
        TextStyle(
          fontSize: widget.style.titleFontSize,
          fontWeight: widget.style.titleFontWeight,
        );
    // 与正文编辑器同款宽度约束 + 水平内边距，使标题左缘与正文左缘对齐。
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth > widget.style.contentWidth
            ? widget.style.contentWidth
            : constraints.maxWidth;
        return Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              52,
              42,
              52,
              widget.style.titleBottomSpacing,
            ),
            child: SizedBox(
              width: width,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    ChapterTitleText.prefix(widget.chapterNumber),
                    style: titleStyle,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      autofocus: widget.autofocusSubtitle,
                      maxLines: 1,
                      minLines: 1,
                      // 用 done 而非 next：next 会触发 Flutter 默认的焦点遍历，
                      // 把焦点送到目录树等下一个可聚焦控件。done 仅触发 onSubmitted，
                      // 由我们在其中显式把焦点交给正文。
                      textInputAction: TextInputAction.done,
                      textAlign: TextAlign.start,
                      style: titleStyle,
                      cursorColor: EditorCaret.color(colorScheme),
                      cursorWidth: EditorCaret.width,
                      cursorRadius: EditorCaret.radius,
                      cursorHeight: EditorCaret.heightFor(
                        widget.style.titleFontSize,
                      ),
                      decoration: const InputDecoration(
                        isCollapsed: true,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                      ),
                      onChanged: (value) {
                        if (_syncing) {
                          return;
                        }
                        widget.onChanged(value);
                      },
                      onSubmitted: (_) => widget.onEnter?.call(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
