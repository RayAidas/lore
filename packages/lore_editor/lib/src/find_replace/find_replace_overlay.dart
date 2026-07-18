import 'package:flutter/material.dart';

import '../lore_text_controller.dart';
import 'find_replace_controller.dart';

/// 底部贴附的查找替换面板。
///
/// 高亮当前匹配只设置 [LoreTextController.selection]，不改文本，让
/// [TextField] 自动滚动到选区。替换时把新文本写回 controller.value，
/// value setter 会 bump 编辑版本并触发上层自动保存。
///
/// 为在用户输入时刷新匹配，本组件监听编辑器 controller；但用
/// [LoreTextController.editVersion] 守卫，避免"重算→设选区→又触发重算"
/// 的死循环（设选区不 bump 版本）。
final class FindReplaceOverlay extends StatelessWidget {
  const FindReplaceOverlay({
    required this.findController,
    required this.editorController,
    this.initialShowReplace = false,
    this.onClose,
    super.key,
  });

  final FindReplaceController findController;
  final LoreTextController editorController;
  final bool initialShowReplace;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return _FindReplaceOverlayStateful(
      findController: findController,
      editorController: editorController,
      initialShowReplace: initialShowReplace,
      onClose: onClose,
    );
  }
}

final class _FindReplaceOverlayStateful extends StatefulWidget {
  const _FindReplaceOverlayStateful({
    required this.findController,
    required this.editorController,
    required this.initialShowReplace,
    this.onClose,
  });

  final FindReplaceController findController;
  final LoreTextController editorController;
  final bool initialShowReplace;
  final VoidCallback? onClose;

  @override
  State<_FindReplaceOverlayStateful> createState() =>
      _FindReplaceOverlayStatefulState();
}

final class _FindReplaceOverlayStatefulState
    extends State<_FindReplaceOverlayStateful> {
  late final TextEditingController _patternField;
  late final TextEditingController _replaceField;
  late bool _showReplace;
  int? _lastEditVersion;

  @override
  void initState() {
    super.initState();
    _patternField = TextEditingController(text: widget.findController.pattern);
    _replaceField = TextEditingController(
      text: widget.findController.replacement,
    );
    _showReplace = widget.initialShowReplace;
    _lastEditVersion = widget.editorController.editVersion;
    widget.findController.addListener(_handleFindChanged);
    widget.editorController.addListener(_handleEditorChanged);
    _applyCurrentSelection();
  }

  @override
  void dispose() {
    widget.findController.removeListener(_handleFindChanged);
    widget.editorController.removeListener(_handleEditorChanged);
    _patternField.dispose();
    _replaceField.dispose();
    super.dispose();
  }

  /// 匹配/游标变化时，把当前匹配同步为编辑器选区（仅 selection，不改文本）。
  void _handleFindChanged() {
    _applyCurrentSelection();
  }

  /// 编辑器变化时，仅在文本真正改变（editVersion 变）时重算匹配；
  /// 选区变化（含本组件设入的选区）不会触发重算，避免死循环。
  void _handleEditorChanged() {
    final version = widget.editorController.editVersion;
    if (version == _lastEditVersion) {
      return;
    }
    _lastEditVersion = version;
    widget.findController.recompute(widget.editorController.text);
  }

  void _applyCurrentSelection() {
    final match = widget.findController.currentMatch;
    if (match == null) {
      return;
    }
    widget.editorController.selection = TextSelection(
      baseOffset: match.start,
      extentOffset: match.end,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = widget.findController;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Material(
          color: theme.colorScheme.surfaceContainerLow,
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: _showReplace ? '隐藏替换' : '显示替换',
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          setState(() => _showReplace = !_showReplace),
                      icon: Icon(
                        _showReplace ? Icons.expand_more : Icons.chevron_right,
                        size: 20,
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _patternField,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: '查找',
                          suffixText: controller.matchCount == 0
                              ? '无匹配'
                              : '${controller.currentIndex + 1}/${controller.matchCount}',
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: '上一个',
                                visualDensity: VisualDensity.compact,
                                onPressed: controller.matchCount == 0
                                    ? null
                                    : controller.previous,
                                icon: const Icon(
                                  Icons.keyboard_arrow_up,
                                  size: 20,
                                ),
                              ),
                              IconButton(
                                tooltip: '下一个',
                                visualDensity: VisualDensity.compact,
                                onPressed: controller.matchCount == 0
                                    ? null
                                    : controller.next,
                                icon: const Icon(
                                  Icons.keyboard_arrow_down,
                                  size: 20,
                                ),
                              ),
                              IconButton(
                                tooltip: '区分大小写',
                                visualDensity: VisualDensity.compact,
                                color: controller.caseSensitive
                                    ? theme.colorScheme.primary
                                    : null,
                                onPressed: () => controller.setCaseSensitive(
                                  !controller.caseSensitive,
                                ),
                                icon: const Icon(Icons.text_fields, size: 18),
                              ),
                              IconButton(
                                tooltip: '正则表达式',
                                visualDensity: VisualDensity.compact,
                                color: controller.useRegex
                                    ? theme.colorScheme.primary
                                    : null,
                                onPressed: () => controller.setUseRegex(
                                  !controller.useRegex,
                                ),
                                icon: const Icon(Icons.code, size: 18),
                              ),
                              IconButton(
                                tooltip: '关闭',
                                visualDensity: VisualDensity.compact,
                                onPressed: widget.onClose,
                                icon: const Icon(Icons.close, size: 18),
                              ),
                            ],
                          ),
                        ),
                        onChanged: (value) {
                          controller.setPattern(value);
                          controller.setReplacement(_replaceField.text);
                        },
                        onSubmitted: (_) => controller.next(),
                      ),
                    ),
                  ],
                ),
                if (_showReplace)
                  Padding(
                    padding: const EdgeInsets.only(left: 48, top: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _replaceField,
                            decoration: const InputDecoration(
                              isDense: true,
                              hintText: '替换为',
                            ),
                            onChanged: controller.setReplacement,
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: controller.currentMatch == null
                              ? null
                              : _replaceCurrent,
                          child: const Text('替换'),
                        ),
                        FilledButton.tonal(
                          onPressed: controller.matchCount == 0
                              ? null
                              : _replaceAll,
                          child: const Text('全部替换'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _replaceCurrent() {
    final result = widget.findController.applyReplaceCurrent(
      widget.editorController.text,
    );
    if (!result.replaced) {
      return;
    }
    _writeBack(result.text, result.cursor);
    _lastEditVersion = widget.editorController.editVersion;
    widget.findController.recompute(result.text);
  }

  void _replaceAll() {
    final newText = widget.findController.applyReplaceAll(
      widget.editorController.text,
    );
    _writeBack(newText, null);
    _lastEditVersion = widget.editorController.editVersion;
    widget.findController.recompute(newText);
  }

  void _writeBack(String text, int? cursor) {
    widget.editorController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: (cursor ?? text.length).clamp(0, text.length),
      ),
    );
  }
}
