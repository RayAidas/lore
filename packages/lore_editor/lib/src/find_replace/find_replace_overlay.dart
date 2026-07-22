import 'dart:async';

import 'package:flutter/material.dart';

import '../document_controller.dart';
import '../large_text/lore_large_text_controller.dart';
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
  final LoreDocumentController editorController;
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
  final LoreDocumentController editorController;
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
  Timer? _recomputeTimer;

  /// 文本量低于该阈值时查找直接走同步路径——小文档匹配很快，无须为它
  /// 承担 150ms 防抖 + isolate 启动的延迟；大文档才需要异步化避免卡顿。
  static const _asyncSearchThreshold = 262144; // 256 KiB (UTF-16 code units)

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
    // initState 处于 build 阶段：设 selection / setFindMatches 会 notify，连锁触发
    // OpenDocument.notifyChanged → 别处 ListenableBuilder markNeedsBuild（"called
    // during build"）。延迟到首帧后（框架解锁）再同步初始选区与整文高亮。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applyCurrentSelection();
      _pushFindMatches();
    });
  }

  @override
  void dispose() {
    widget.findController.removeListener(_handleFindChanged);
    widget.editorController.removeListener(_handleEditorChanged);
    // 关闭面板清除整文高亮：dispose 发生在 widget tree locked 阶段（unmount），
    // 不能同步 notify（会触发 ListenableBuilder.markNeedsBuild 而崩，且连锁触发
    // OpenDocument.notifyChanged）。延迟到下一帧框架解锁后再清；若 editorController
    // 已随文档关闭而 dispose，setFindMatches 的 _disposed 守卫会安全跳过。
    final ec = widget.editorController;
    if (ec is LoreLargeTextController) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ec.setFindMatches(const []);
      });
    }
    _recomputeTimer?.cancel();
    _patternField.dispose();
    _replaceField.dispose();
    super.dispose();
  }

  // 跨章节连续点不同结果时，外层 FindReplaceController 实例更换，但本 Stateful 的
  // canUpdate 仅看 runtimeType+key（无 key），故 Flutter 走 update 而非 remount、
  // State 复用——必须在此切走旧监听、按新 controller 重推选区与整文高亮。
  // 切勿为本 widget 加 key 或重写 ==，否则会退化为 remount、绕过此同步路径。
  @override
  void didUpdateWidget(covariant _FindReplaceOverlayStateful oldWidget) {
    super.didUpdateWidget(oldWidget);
    final findChanged = widget.findController != oldWidget.findController;
    final editorChanged = widget.editorController != oldWidget.editorController;
    if (findChanged) {
      oldWidget.findController.removeListener(_handleFindChanged);
      widget.findController.addListener(_handleFindChanged);
    }
    if (editorChanged) {
      oldWidget.editorController.removeListener(_handleEditorChanged);
      widget.editorController.addListener(_handleEditorChanged);
      _lastEditVersion = widget.editorController.editVersion;
    }
    if (findChanged || editorChanged) {
      // 切换章节或 findController 后重新同步选区与整文高亮：跨章节连续点不同结果时
      // overlay State 保持复用（widget update，非 remount），必须切走旧监听、按新
      // controller 重推，否则第二段起既不定位也不高亮。postFrame 避开 build 阶段。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _applyCurrentSelection();
        _pushFindMatches();
      });
    }
  }

  /// 匹配/游标变化时，把当前匹配同步为编辑器选区（仅 selection，不改文本），
  /// 并把整文匹配推给编辑器渲染层做整文高亮。
  void _handleFindChanged() {
    _applyCurrentSelection();
    _pushFindMatches();
  }

  /// 把整文匹配推给编辑器渲染层（仅大文本编辑器支持整文高亮）。
  void _pushFindMatches() {
    final ec = widget.editorController;
    if (ec is LoreLargeTextController) {
      ec.setFindMatches(
        widget.findController.matches,
        currentIndex: widget.findController.currentIndex,
      );
    }
  }

  /// 编辑器变化时，仅在文本真正改变（editVersion 变）时重算匹配；
  /// 选区变化（含本组件设入的选区）不会触发重算，避免死循环。
  void _handleEditorChanged() {
    final version = widget.editorController.editVersion;
    if (version == _lastEditVersion) {
      return;
    }
    _lastEditVersion = version;
    _scheduleRecompute();
  }

  void _scheduleRecompute() {
    _recomputeTimer?.cancel();
    // 用 O(1) 的 length 判阈值，避免大文档每次按键都物化全文（text 是 O(n)）。
    if (widget.editorController.length < _asyncSearchThreshold) {
      widget.findController.recompute(widget.editorController.text);
      return;
    }
    _recomputeTimer = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      // 防抖后才物化全文：之前 text 在 Timer 外读取，每次按键都 O(n) 构造
      // 一个 150ms 内大概率被 cancel 丢弃的字符串。
      final text = widget.editorController.text;
      unawaited(widget.findController.recomputeAsync(text));
    });
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
    // 程序设 selection 不会触发编辑器自动滚动，显式请求把匹配滚入视口。
    final ec = widget.editorController;
    if (ec is LoreLargeTextController) {
      ec.requestReveal(match.start);
    }
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
                                onPressed: () {
                                  controller.setCaseSensitive(
                                    !controller.caseSensitive,
                                  );
                                  _scheduleRecompute();
                                },
                                icon: const Icon(Icons.text_fields, size: 18),
                              ),
                              IconButton(
                                tooltip: '正则表达式',
                                visualDensity: VisualDensity.compact,
                                color: controller.useRegex
                                    ? theme.colorScheme.primary
                                    : null,
                                onPressed: () {
                                  controller.setUseRegex(!controller.useRegex);
                                  _scheduleRecompute();
                                },
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
                          _scheduleRecompute();
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
    // 写回会 bump editVersion 触发 _handleEditorChanged 排一个延迟重算，
    // 这里已经同步重算过，把那个冗余的异步重算取消掉。
    _recomputeTimer?.cancel();
    widget.findController.recompute(result.text);
  }

  void _replaceAll() {
    final newText = widget.findController.applyReplaceAll(
      widget.editorController.text,
    );
    _writeBack(newText, null);
    _lastEditVersion = widget.editorController.editVersion;
    _recomputeTimer?.cancel();
    widget.findController.recompute(newText);
  }

  void _writeBack(String text, int? cursor) {
    widget.editorController.replaceAllText(
      text,
      selection: TextSelection.collapsed(
        offset: (cursor ?? text.length).clamp(0, text.length),
      ),
    );
  }
}
