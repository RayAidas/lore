import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../editor_style.dart';
import 'lore_large_text_controller.dart';

final class LoreLargeTextEditor extends StatefulWidget {
  const LoreLargeTextEditor({
    required this.controller,
    required this.scrollController,
    this.style = const EditorStyle.defaults(),
    this.autofocus = false,
    super.key,
  });

  final LoreLargeTextController controller;
  final ScrollController scrollController;
  final EditorStyle style;
  final bool autofocus;

  @override
  State<LoreLargeTextEditor> createState() => _LoreLargeTextEditorState();
}

final class _LoreLargeTextEditorState extends State<LoreLargeTextEditor> {
  final _blockRegistry = _BlockGeometryRegistry();
  int? _pointerSelectionAnchor;
  var _globalSelectionDrag = false;
  late int _observedBlocksRevision;

  @override
  void initState() {
    super.initState();
    _observedBlocksRevision = widget.controller.blocksRevision;
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant LoreLargeTextEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
    // 打字机模式从关闭切到开启时立即校准一次，无需等下一次按键。
    if (!oldWidget.style.typewriterMode && widget.style.typewriterMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _recenterCaretIfNeeded();
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    final blocksChanged =
        _observedBlocksRevision != widget.controller.blocksRevision;
    _observedBlocksRevision = widget.controller.blocksRevision;
    if (mounted) {
      setState(() {});
      if (blocksChanged) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || widget.controller.length == 0) {
            return;
          }
          _blockRegistry.focusBlock(
            widget.controller.blockIndexForOffset(
              widget.controller.selection.extentOffset,
            ),
            widget.controller,
          );
        });
      }
      // 打字机模式：每次编辑/选区变化后把光标行滚动到视口中央。post-frame
      // 等重排落定、光标几何有效；拖拽守卫避免与鼠标选区/手动滚动打架。
      if (widget.style.typewriterMode) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _recenterCaretIfNeeded();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width > widget.style.contentWidth
        ? widget.style.contentWidth
        : MediaQuery.sizeOf(context).width;
    // 专注模式：仅含光标的段落保持全不透明，其余淡化。选区无效时回退为
    // "不淡化任何段"，避免出现整篇被淡化的破损观感。
    final focusMode = widget.style.focusMode;
    final selectionValid =
        focusMode && widget.controller.selection.isValid;
    final activeBlockIndex = selectionValid
        ? widget.controller.blockIndexForOffset(
            widget.controller.selection.extentOffset,
          )
        : -1;
    return Focus(
      canRequestFocus: false,
      onKeyEvent: (_, event) => _handleRootKey(event),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
              widget.controller.undo,
          const SingleActivator(
            LogicalKeyboardKey.keyZ,
            meta: true,
            shift: true,
          ): widget.controller.redo,
          const SingleActivator(LogicalKeyboardKey.keyA, meta: true): () {
            _selectAll();
          },
          const SingleActivator(LogicalKeyboardKey.keyC, meta: true): _copy,
          const SingleActivator(LogicalKeyboardKey.keyX, meta: true): _cut,
          const SingleActivator(LogicalKeyboardKey.keyV, meta: true): _paste,
        },
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _handlePointerDown,
              onPointerMove: _handlePointerMove,
              onPointerUp: _handlePointerEnd,
              onPointerCancel: _handlePointerEnd,
              child: ListView.builder(
                controller: widget.scrollController,
                padding: const EdgeInsets.symmetric(
                  horizontal: 52,
                  vertical: 42,
                ),
                itemCount: widget.controller.blocks.length,
                itemBuilder: (context, index) {
                  final block = widget.controller.blocks[index];
                  return _LargeTextBlockField(
                    key: ValueKey(index),
                    block: block,
                    blockIndex: index,
                    documentController: widget.controller,
                    registry: _blockRegistry,
                    globalSelectionDrag: _globalSelectionDrag,
                    style: widget.style,
                    autofocus: widget.autofocus && index == 0,
                    dimmed: selectionValid && index != activeBlockIndex,
                    onFocused: () {},
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  KeyEventResult _handleRootKey(KeyEvent event) {
    if (event is! KeyDownEvent || !HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.keyA:
        _selectAll();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyC:
        _copy();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyX:
        _cut();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyV:
        _paste();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  void _selectAll() {
    widget.controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.controller.length,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final index in _blockRegistry.indices) {
        _blockRegistry.applySelection(index, widget.controller);
      }
    });
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (event.buttons != kPrimaryMouseButton) {
      return;
    }
    final anchor = _blockRegistry.documentOffsetFor(
      event.position,
      widget.controller,
    );
    if (anchor == null) {
      return;
    }
    _pointerSelectionAnchor = anchor;
    _blockRegistry.focusBlock(
      widget.controller.blockIndexForOffset(anchor),
      widget.controller,
    );
    widget.controller.beginSelectionDrag();
    setState(() => _globalSelectionDrag = true);
    widget.controller.selection = TextSelection.collapsed(offset: anchor);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final anchor = _pointerSelectionAnchor;
    if (anchor == null || event.buttons != kPrimaryMouseButton) {
      return;
    }
    final extent = _blockRegistry.documentOffsetFor(
      event.position,
      widget.controller,
    );
    if (extent == null) {
      _autoScroll(event.position);
      return;
    }
    widget.controller.selection = TextSelection(
      baseOffset: anchor,
      extentOffset: extent,
    );
    _autoScroll(event.position);
  }

  void _handlePointerEnd(PointerEvent event) {
    _pointerSelectionAnchor = null;
    widget.controller.endSelectionDrag();
    if (_globalSelectionDrag) {
      setState(() => _globalSelectionDrag = false);
    }
  }

  void _autoScroll(Offset globalPosition) {
    if (!widget.scrollController.hasClients) {
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }
    final local = box.globalToLocal(globalPosition);
    const edge = 36.0;
    var delta = 0.0;
    if (local.dy < edge) {
      delta = -18;
    } else if (local.dy > box.size.height - edge) {
      delta = 18;
    }
    if (delta == 0) {
      return;
    }
    final position = widget.scrollController.position;
    widget.scrollController.jumpTo(
      (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  /// 打字机模式：把光标所在行滚动到视口垂直居中。
  ///
  /// 光标当前在编辑器局部坐标的 Y 为 [caretLocalY]，目标为视口高度的一半；
  /// 滚动 [delta = caretLocalY - target] 个像素即可（光标在中心下方时 delta>0，
  /// 增大 pixels 向下滚，把光标上移到中心）。8px 死区避免每次按键微抖。
  void _recenterCaretIfNeeded() {
    if (!mounted ||
        !widget.style.typewriterMode ||
        widget.controller.selectionDragActive ||
        _globalSelectionDrag ||
        !widget.scrollController.hasClients) {
      return;
    }
    final editorBox = context.findRenderObject() as RenderBox?;
    final caretGlobalY = _blockRegistry.focusedCaretCenterY();
    if (editorBox == null || caretGlobalY == null) {
      return;
    }
    final caretLocalY = editorBox.globalToLocal(Offset(0, caretGlobalY)).dy;
    final target = editorBox.size.height / 2;
    final delta = caretLocalY - target;
    if (delta.abs() < 8) {
      return;
    }
    final position = widget.scrollController.position;
    widget.scrollController.jumpTo(
      (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  Future<void> _copy() async {
    final selection = widget.controller.selection;
    if (selection.isCollapsed) {
      return;
    }
    await Clipboard.setData(
      ClipboardData(
        text: widget.controller.text.substring(selection.start, selection.end),
      ),
    );
  }

  Future<void> _cut() async {
    await _copy();
    if (!widget.controller.selection.isCollapsed) {
      widget.controller.replaceSelection('');
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text case final text?) {
      widget.controller.replaceSelection(text);
    }
  }
}

final class _LargeTextBlockField extends StatefulWidget {
  const _LargeTextBlockField({
    required this.block,
    required this.blockIndex,
    required this.documentController,
    required this.registry,
    required this.globalSelectionDrag,
    required this.style,
    required this.autofocus,
    required this.dimmed,
    required this.onFocused,
    super.key,
  });

  final LargeTextBlock block;
  final int blockIndex;
  final LoreLargeTextController documentController;
  final _BlockGeometryRegistry registry;
  final bool globalSelectionDrag;
  final EditorStyle style;
  final bool autofocus;
  final bool dimmed;
  final VoidCallback onFocused;

  @override
  State<_LargeTextBlockField> createState() => _LargeTextBlockFieldState();
}

final class _LargeTextBlockFieldState extends State<_LargeTextBlockField> {
  late final TextEditingController _textController;
  late final FocusNode _focusNode;
  var _updating = false;
  late String _observedText;

  // 鼠标拖拽选区时，onPointerMove 每秒触发几十次 hit-test，同时高亮重绘
  // 也会每次 paint 都重建 TextPainter。对整段 block 文本（单段最大 8K 码元）
  // 反复 layout 会明显卡顿。这里按 (text, style, direction, scaler, width)
  // 缓存一份已 layout 的 painter，hit-test 与选区绘制共用——拖拽期间这些
  // 输入都不会变，从而两个热路径都能命中缓存。
  TextPainter? _layoutPainter;
  String? _layoutText;
  TextStyle? _layoutStyle;
  TextDirection? _layoutDirection;
  TextScaler? _layoutScaler;
  double? _layoutWidth;

  @override
  void initState() {
    super.initState();
    _observedText = widget.block.text;
    _textController = TextEditingController(text: _observedText)
      ..addListener(_handleLocalChanged);
    _focusNode = FocusNode(onKeyEvent: _handleFocusedKey)
      ..addListener(_handleFocusChanged);
    widget.registry.register(widget.blockIndex, this);
  }

  @override
  void didUpdateWidget(covariant _LargeTextBlockField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.blockIndex != widget.blockIndex ||
        oldWidget.registry != widget.registry) {
      oldWidget.registry.unregister(oldWidget.blockIndex, this);
      widget.registry.register(widget.blockIndex, this);
    }
    if (widget.block.text != _observedText) {
      _updating = true;
      _observedText = widget.block.text;
      final documentSelection = widget.documentController.selection;
      final blockStart = widget.documentController.blockStart(
        widget.blockIndex,
      );
      _textController.value = TextEditingValue(
        text: _observedText,
        selection: _localSelection(documentSelection, blockStart),
      );
      _updating = false;
    } else {
      applyDocumentSelection();
    }
  }

  @override
  void dispose() {
    widget.registry.unregister(widget.blockIndex, this);
    _layoutPainter?.dispose();
    _textController
      ..removeListener(_handleLocalChanged)
      ..dispose();
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) {
      return;
    }
    widget.onFocused();
    _syncSelection();
  }

  KeyEventResult _handleFocusedKey(FocusNode node, KeyEvent event) {
    return handleBoundaryKey(event, widget.documentController);
  }

  void focusAt(TextSelection globalSelection) {
    final blockStart = widget.documentController.blockStart(widget.blockIndex);
    _updating = true;
    _focusNode.requestFocus();
    _textController.selection = _localSelection(globalSelection, blockStart);
    _updating = false;
  }

  KeyEventResult handleBoundaryKey(
    KeyEvent event,
    LoreLargeTextController controller,
  ) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final selection = controller.selection;
    final blockStart = controller.blockStart(widget.blockIndex);
    final blockEnd = blockStart + widget.block.text.length;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final isMeta = HardwareKeyboard.instance.isMetaPressed;
    final isSelectAll = isMeta && event.logicalKey == LogicalKeyboardKey.keyA;
    final isBackspace = event.logicalKey == LogicalKeyboardKey.backspace;
    final isDelete = event.logicalKey == LogicalKeyboardKey.delete;
    if (isSelectAll) {
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.length,
      );
      return KeyEventResult.handled;
    }
    if (isBackspace || isDelete) {
      if (_textController.value.composing.isValid &&
          !_textController.value.composing.isCollapsed) {
        return KeyEventResult.ignored;
      }
      if (!selection.isCollapsed) {
        controller.replaceSelection('');
        return KeyEventResult.handled;
      }
      if (isBackspace) {
        if (selection.extentOffset > blockStart) {
          return KeyEventResult.ignored;
        } else if (widget.blockIndex > 0) {
          controller.replaceRange(blockStart - 1, blockStart, '');
        } else {
          return KeyEventResult.ignored;
        }
      } else if (selection.extentOffset < blockEnd) {
        return KeyEventResult.ignored;
      } else if (widget.block.hasLineBreak) {
        controller.replaceRange(blockEnd, blockEnd + 1, '');
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    final isLeft = event.logicalKey == LogicalKeyboardKey.arrowLeft;
    final isRight = event.logicalKey == LogicalKeyboardKey.arrowRight;
    if (!isLeft && !isRight) {
      return KeyEventResult.ignored;
    }
    if (!shift && !selection.isCollapsed) {
      controller.selection = TextSelection.collapsed(
        offset: isLeft ? selection.start : selection.end,
      );
      widget.registry.focusBlock(
        controller.blockIndexForOffset(controller.selection.extentOffset),
        controller,
      );
      return KeyEventResult.handled;
    }
    final atBoundary = isLeft
        ? selection.isCollapsed && selection.extentOffset <= blockStart
        : selection.isCollapsed && selection.extentOffset >= blockEnd;
    if (!atBoundary) {
      return KeyEventResult.ignored;
    }
    final adjacent = widget.blockIndex + (isLeft ? -1 : 1);
    if (adjacent < 0 || adjacent >= controller.blocks.length) {
      return KeyEventResult.ignored;
    }
    final adjacentStart = controller.blockStart(adjacent);
    final adjacentEnd = adjacentStart + controller.blocks[adjacent].text.length;
    final nextExtent = isLeft ? adjacentEnd : adjacentStart;
    controller.selection = shift
        ? TextSelection(
            baseOffset: selection.baseOffset,
            extentOffset: nextExtent,
          )
        : TextSelection.collapsed(offset: nextExtent);
    widget.registry.focusBlock(adjacent, controller);
    return KeyEventResult.handled;
  }

  void _handleLocalChanged() {
    if (_updating) {
      return;
    }
    final composing = _textController.value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      return;
    }
    final nextText = _textController.text;
    if (nextText == _observedText) {
      _syncSelection();
      return;
    }
    final oldText = _observedText;
    var prefix = 0;
    while (prefix < oldText.length &&
        prefix < nextText.length &&
        oldText.codeUnitAt(prefix) == nextText.codeUnitAt(prefix)) {
      prefix += 1;
    }
    var suffix = 0;
    while (suffix < oldText.length - prefix &&
        suffix < nextText.length - prefix &&
        oldText.codeUnitAt(oldText.length - suffix - 1) ==
            nextText.codeUnitAt(nextText.length - suffix - 1)) {
      suffix += 1;
    }
    final replacement = nextText.substring(prefix, nextText.length - suffix);
    final removedEnd = oldText.length - suffix;
    _observedText = nextText;
    if (!widget.documentController.selection.isCollapsed) {
      widget.documentController.replaceSelection(replacement);
      return;
    }
    widget.documentController.replaceBlockRange(
      widget.blockIndex,
      prefix,
      removedEnd,
      replacement,
      _textController.selection,
    );
  }

  void _syncSelection() {
    if (!_focusNode.hasFocus ||
        widget.globalSelectionDrag ||
        widget.documentController.selectionDragActive ||
        !_textController.selection.isValid) {
      return;
    }
    final blockStart = widget.documentController.blockStart(widget.blockIndex);
    final documentSelection = widget.documentController.selection;
    if (!documentSelection.isCollapsed &&
        _textController.selection ==
            _localSelection(documentSelection, blockStart)) {
      return;
    }
    widget.documentController.selection = TextSelection(
      baseOffset: blockStart + _textController.selection.baseOffset,
      extentOffset: blockStart + _textController.selection.extentOffset,
      affinity: _textController.selection.affinity,
      isDirectional: _textController.selection.isDirectional,
    );
  }

  void applyDocumentSelection() {
    final blockStart = widget.documentController.blockStart(widget.blockIndex);
    final nextSelection = _localSelection(
      widget.documentController.selection,
      blockStart,
    );
    if (_textController.selection == nextSelection) {
      return;
    }
    _updating = true;
    _textController.selection = nextSelection;
    _updating = false;
  }

  bool get hasFocus => _focusNode.hasFocus;

  /// 返回当前光标（选区 extent）所在行的垂直中点（全局坐标），用于打字机模式
  /// 把光标行滚动到视口中央。无法计算（未 layout、选区无效）时返回 null。
  /// 复用已缓存的 `_layoutPainterFor`，避免重复 layout。
  double? caretCenter() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) {
      return null;
    }
    final selection = _textController.selection;
    if (!selection.isValid) {
      return null;
    }
    final localExtent = selection.extentOffset.clamp(
      0,
      widget.block.text.length,
    );
    final textStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
      height: widget.style.lineHeight,
      fontSize: widget.style.fontSize,
      letterSpacing: widget.style.letterSpacing,
    );
    final painter = _layoutPainterFor(
      text: widget.block.text,
      style: textStyle,
      direction: Directionality.of(context),
      scaler: MediaQuery.textScalerOf(context),
      width: box.size.width,
    );
    final caretTop = painter.getOffsetForCaret(
      TextPosition(offset: localExtent),
      Rect.zero,
    );
    final lineCenter = caretTop.dy + painter.preferredLineHeight / 2;
    return box.localToGlobal(Offset(0, lineCenter)).dy;
  }

  int? documentOffsetFor(Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) {
      return null;
    }
    final local = box.globalToLocal(globalPosition);
    if (local.dy < 0 || local.dy > box.size.height) {
      return null;
    }
    final textStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
      height: widget.style.lineHeight,
      fontSize: widget.style.fontSize,
      letterSpacing: widget.style.letterSpacing,
    );
    final painter = _layoutPainterFor(
      text: widget.block.text,
      style: textStyle,
      direction: Directionality.of(context),
      scaler: MediaQuery.textScalerOf(context),
      width: box.size.width,
    );
    final localOffset = painter
        .getPositionForOffset(local)
        .offset
        .clamp(0, widget.block.text.length);
    return widget.documentController.blockStart(widget.blockIndex) +
        localOffset;
  }

  TextPainter _layoutPainterFor({
    required String text,
    required TextStyle? style,
    required TextDirection direction,
    required TextScaler scaler,
    required double width,
  }) {
    if (_layoutPainter != null &&
        _layoutText == text &&
        _layoutStyle == style &&
        _layoutDirection == direction &&
        _layoutScaler == scaler &&
        _layoutWidth == width) {
      return _layoutPainter!;
    }
    _layoutPainter?.dispose();
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      textScaler: scaler,
    )..layout(maxWidth: width);
    _layoutPainter = painter;
    _layoutText = text;
    _layoutStyle = style;
    _layoutDirection = direction;
    _layoutScaler = scaler;
    _layoutWidth = width;
    return painter;
  }

  TextSelection _localSelection(TextSelection document, int blockStart) {
    final blockEnd = blockStart + widget.block.text.length;
    return TextSelection(
      baseOffset: document.baseOffset.clamp(blockStart, blockEnd) - blockStart,
      extentOffset:
          document.extentOffset.clamp(blockStart, blockEnd) - blockStart,
      affinity: document.affinity,
      isDirectional: document.isDirectional,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
      height: widget.style.lineHeight,
      fontSize: widget.style.fontSize,
      letterSpacing: widget.style.letterSpacing,
    );
    final blockStart = widget.documentController.blockStart(widget.blockIndex);
    final selection = widget.documentController.selection;
    final localStart = (selection.start - blockStart).clamp(
      0,
      widget.block.text.length,
    );
    final localEnd = (selection.end - blockStart).clamp(
      0,
      widget.block.text.length,
    );
    final selectionColor =
        TextSelectionTheme.of(context).selectionColor ??
        Theme.of(context).colorScheme.primary.withValues(alpha: 0.28);
    final textDirection = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    // 选区绘制借用 state 的 layout 缓存：paint 时不再新建 TextPainter，而是
    // 复用 hit-test 已经 layout 好的同一份 painter（输入完全一致）。
    TextPainter layoutFor(double width) => _layoutPainterFor(
      text: widget.block.text,
      style: textStyle,
      direction: textDirection,
      scaler: textScaler,
      width: width,
    );
    final content = Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _BlockSelectionPainter(
                text: widget.block.text,
                style: textStyle,
                selection: TextSelection(
                  baseOffset: localStart,
                  extentOffset: localEnd,
                ),
                color: selectionColor,
                textDirection: textDirection,
                textScaler: textScaler,
                layoutFor: layoutFor,
              ),
            ),
          ),
        ),
        TextSelectionTheme(
          data: const TextSelectionThemeData(
            selectionColor: Colors.transparent,
          ),
          child: TextField(
            controller: _textController,
            focusNode: _focusNode,
            enableInteractiveSelection: false,
            autofocus: widget.autofocus,
            maxLines: null,
            minLines: 1,
            keyboardType: TextInputType.multiline,
            style: textStyle,
            decoration: const InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
              filled: false,
            ),
          ),
        ),
      ],
    );
    return Focus(
      onKeyEvent: (_, event) => widget.registry.handleKey(
        widget.blockIndex,
        event,
        widget.documentController,
      ),
      // 专注模式：淡化非当前段落。Opacity 不影响命中测试，点击淡化段落
      // 仍可聚焦它，焦点移过去后该段恢复全不透明。
      child: widget.dimmed ? Opacity(opacity: 0.28, child: content) : content,
    );
  }
}

final class _BlockSelectionPainter extends CustomPainter {
  _BlockSelectionPainter({
    required this.text,
    required this.style,
    required this.selection,
    required this.color,
    required this.textDirection,
    required this.textScaler,
    required this.layoutFor,
  });

  final String text;
  // style/textDirection/textScaler 现在只用于 shouldRepaint 的比较——paint
  // 不再自己 layout，而是通过 [layoutFor] 借用 state 缓存的已 layout painter。
  final TextStyle? style;
  final TextSelection selection;
  final Color color;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final TextPainter Function(double width) layoutFor;

  @override
  void paint(Canvas canvas, Size size) {
    if (selection.isCollapsed || text.isEmpty) return;
    final painter = layoutFor(size.width);
    final paint = Paint()..color = color;
    for (final box in painter.getBoxesForSelection(selection)) {
      canvas.drawRect(box.toRect(), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BlockSelectionPainter oldDelegate) {
    // 故意不比较 [layoutFor]：闭包没有有意义的相等性，且它的输入已被
    // text/style/textDirection/textScaler 覆盖，这些字段变了自然会重绘。
    return oldDelegate.text != text ||
        oldDelegate.style != style ||
        oldDelegate.selection != selection ||
        oldDelegate.color != color ||
        oldDelegate.textDirection != textDirection ||
        oldDelegate.textScaler != textScaler;
  }
}

final class _BlockGeometryRegistry {
  final Map<int, _LargeTextBlockFieldState> _states = {};

  Iterable<int> get indices => _states.keys;

  void register(int index, _LargeTextBlockFieldState state) {
    _states[index] = state;
  }

  void unregister(int index, _LargeTextBlockFieldState state) {
    if (identical(_states[index], state)) {
      _states.remove(index);
    }
  }

  KeyEventResult handleKey(
    int index,
    KeyEvent event,
    LoreLargeTextController controller,
  ) {
    final state = _states[index];
    if (state == null) {
      return KeyEventResult.ignored;
    }
    return state.handleBoundaryKey(event, controller);
  }

  void focusBlock(int index, LoreLargeTextController controller) {
    final state = _states[index];
    if (state == null) {
      return;
    }
    state.focusAt(controller.selection);
  }

  void applySelection(int index, LoreLargeTextController controller) {
    _states[index]?.applyDocumentSelection();
  }

  /// 返回当前聚焦 block 的光标行垂直中点（全局坐标），供打字机模式居中。
  /// 无 block 聚焦时返回 null。
  double? focusedCaretCenterY() {
    for (final state in _states.values) {
      if (state.hasFocus) {
        return state.caretCenter();
      }
    }
    return null;
  }

  int? documentOffsetFor(
    Offset globalPosition,
    LoreLargeTextController controller,
  ) {
    final entries = _states.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    for (final entry in entries) {
      final offset = entry.value.documentOffsetFor(globalPosition);
      if (offset != null) {
        return offset.clamp(0, controller.length);
      }
    }
    return null;
  }
}
