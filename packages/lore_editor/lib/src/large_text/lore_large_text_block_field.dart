part of 'lore_large_text_editor.dart';

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
    required this.drawTopGridLine,
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

  /// 是否在该段顶部多画一条网格线（代表上一段空行底部、即本段上方）。仅当
  /// 本 block 是新段落首块（前一 block 的 [LargeTextBlock.hasLineBreak] 为真）
  /// 且非全文首段时为 true——首段上方不画。
  final bool drawTopGridLine;

  final VoidCallback onFocused;

  @override
  State<_LargeTextBlockField> createState() => _LargeTextBlockFieldState();
}

final class _LargeTextBlockFieldState extends State<_LargeTextBlockField> {
  late final _FindHighlightTextEditingController _textController;
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
    _textController = _FindHighlightTextEditingController(text: _observedText)
      ..addListener(_handleLocalChanged);
    _syncFindHighlights();
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
    _syncFindHighlights();
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
    // 长按方向键时平台在首个 KeyDownEvent 之后持续发 KeyRepeatEvent：若只接
    // KeyDownEvent，跨段逻辑仅在首帧触发，之后 repeat 被忽略 → 光标到段首/段尾
    // 就卡住、无法跨段（单次点按因每次都是 KeyDownEvent 而表现正常）。故 repeat
    // 与 down 一视同仁。KeyUpEvent 仍忽略。
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
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
    // Tab：在光标处插入一字缩进（全角空格）。排除 ⌘/Shift 组合（⌘Tab 是系统
    // 切应用、Shift+Tab 留作反向语义），以及 IME 组字进行中（交还默认，避免
    // 与候选词冲突）。
    final isTab =
        !isMeta && !shift && event.logicalKey == LogicalKeyboardKey.tab;
    if (isTab) {
      return _handleTab(controller);
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
    final isUp = event.logicalKey == LogicalKeyboardKey.arrowUp;
    final isDown = event.logicalKey == LogicalKeyboardKey.arrowDown;
    if (isUp || isDown) {
      return _handleVerticalKey(controller, isUp, shift);
    }
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

  /// 处理 Tab 键：IME 组字进行中放行（交还默认，避免与候选词冲突）；否则在
  /// 光标处插入一字缩进（全角空格 [_tabIndent]），选区非空时替换选区。
  KeyEventResult _handleTab(LoreLargeTextController controller) {
    final composing = _textController.value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      return KeyEventResult.ignored;
    }
    final selection = controller.selection;
    if (selection.isCollapsed) {
      controller.replaceRange(
        selection.extentOffset,
        selection.extentOffset,
        _tabIndent,
      );
    } else {
      controller.replaceSelection(_tabIndent);
    }
    return KeyEventResult.handled;
  }

  /// 处理 ↑/↓：行内移动交还 TextField；命中段首/段末视觉行时跨段，把光标落到
  /// 目标段对应行的同列（用当前 caret 的 X 在目标段里取最近 offset）。Shift
  /// 按下时扩展选区（保持 baseOffset、移动 extentOffset）而非单纯移动。
  ///
  /// 为何用 caret 顶部 Y 判定视觉行而非 getLineBoundary：单段文本经 word-wrap
  /// 可有多视觉行，getOffsetForCaret 给出真实的行内 Y；空段也能正确判为「既首
  /// 既末」。0.5×lineHeight 死区吸收字距/行高微差，避免边界抖动。
  KeyEventResult _handleVerticalKey(
    LoreLargeTextController controller,
    bool upward,
    bool shift,
  ) {
    // 有选区且非扩展：先折叠到光标点（取消选区），不跨段——再按一次↑/↓才真正
    // 移动。与 ←/→ 的「先取消选区、再按方向键才跨段」保持一致，避免选中一段
    // 文字后按↓直接跳到下一段的反直觉行为。
    if (!shift && !controller.selection.isCollapsed) {
      final extent = controller.selection.extentOffset.clamp(
        0,
        controller.length,
      );
      controller.selection = TextSelection.collapsed(offset: extent);
      widget.registry.focusBlock(
        controller.blockIndexForOffset(extent),
        controller,
      );
      return KeyEventResult.handled;
    }
    final blockStart = controller.blockStart(widget.blockIndex);
    final blockText = widget.block.text;
    final localExtent = (controller.selection.extentOffset - blockStart).clamp(
      0,
      blockText.length,
    );
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) {
      return KeyEventResult.ignored;
    }
    final width = box.size.width;
    final textStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
      height: widget.style.lineHeight,
      fontSize: widget.style.fontSize,
      letterSpacing: widget.style.letterSpacing,
      fontFamily: widget.style.fontFamily,
      fontFamilyFallback: widget.style.fontFamilyFallback,
    );
    final painter = _layoutPainterFor(
      text: blockText,
      style: textStyle,
      direction: Directionality.of(context),
      scaler: MediaQuery.textScalerOf(context),
      width: width,
    );
    final caret = painter.getOffsetForCaret(
      TextPosition(offset: localExtent),
      Rect.zero,
    );
    final lineHeight = painter.preferredLineHeight;
    final onEdge = upward
        ? caret.dy < lineHeight * 0.5
        : caret.dy + lineHeight > painter.height - lineHeight * 0.5;
    if (!onEdge) {
      return KeyEventResult.ignored;
    }
    final targetIndex = widget.blockIndex + (upward ? -1 : 1);
    if (targetIndex < 0 || targetIndex >= controller.blocks.length) {
      return KeyEventResult.ignored;
    }
    final targetOffset = _resolveVerticalTarget(
      controller: controller,
      targetIndex: targetIndex,
      upward: upward,
      preferredX: caret.dx,
      width: width,
      textStyle: textStyle,
    );
    controller.selection = shift
        ? TextSelection(
            baseOffset: controller.selection.baseOffset,
            extentOffset: targetOffset,
          )
        : TextSelection.collapsed(offset: targetOffset);
    widget.registry.focusBlock(targetIndex, controller);
    return KeyEventResult.handled;
  }

  /// 在目标段落里按 [preferredX] 取目标行（上行=末行、下行=首行）的最近 offset，
  /// 转成全局 offset。目标段可能未渲染（不在视口），故自建临时 painter 计算，
  /// 不复用当前段缓存；用完即释放。
  int _resolveVerticalTarget({
    required LoreLargeTextController controller,
    required int targetIndex,
    required bool upward,
    required double preferredX,
    required double width,
    required TextStyle? textStyle,
  }) {
    final targetText = controller.blocks[targetIndex].text;
    final painter = TextPainter(
      text: TextSpan(text: targetText, style: textStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: width);
    final lineHeight = painter.preferredLineHeight;
    final targetY = upward
        ? (painter.height - lineHeight * 0.5).clamp(0.0, painter.height)
        : (lineHeight * 0.5).clamp(0.0, painter.height);
    final localOffset = painter
        .getPositionForOffset(Offset(preferredX.clamp(0.0, width), targetY))
        .offset
        .clamp(0, targetText.length);
    painter.dispose();
    return controller.blockStart(targetIndex) + localOffset;
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
      fontFamily: widget.style.fontFamily,
      fontFamilyFallback: widget.style.fontFamilyFallback,
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
      fontFamily: widget.style.fontFamily,
      fontFamilyFallback: widget.style.fontFamilyFallback,
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

  /// 落在本 block 内的高亮子集:全局区间与 `[blockStart, blockStart+blockLength)`
  /// 求交、平移到局部坐标,颜色叠加渲染透明度。跨 chunk 边界的高亮自动分摊到
  /// 各 block(每块只画交集)。
  ///
  /// 输出为统一的 [TextAnnotation]（仅 background）——highlight 与 diff 共用此
  /// 标注模型，由 `_BlockHighlightPainter` 按背景色绘制。
  List<TextAnnotation> _localHighlightsForBlock(
    int blockStart,
    int blockLength,
  ) {
    final highlights = widget.documentController.highlights;
    if (highlights.isEmpty || blockLength == 0) return const [];
    final blockEnd = blockStart + blockLength;
    final result = <TextAnnotation>[];
    for (final h in highlights) {
      if (h.end <= blockStart || h.start >= blockEnd) continue;
      final localStart = (h.start - blockStart).clamp(0, blockLength);
      final localEnd = (h.end - blockStart).clamp(0, blockLength);
      if (localEnd <= localStart) continue;
      result.add(
        TextAnnotation(
          start: localStart,
          end: localEnd,
          background: Color(h.colorArgb).withValues(alpha: 0.35),
        ),
      );
    }
    return result;
  }

  /// 落在本 block 内的查找匹配高亮：把全局 [LoreLargeTextController.findMatches]
  /// 与本 block 求交、平移到局部坐标，普通匹配浅色、当前匹配（[findCurrentIndex]）
  /// 深色。复用 [_BlockHighlightPainter]，与持久化 highlight 同一渲染机制；这是
  /// `TextAnnotation` 注释里预留的「搜索高亮」复用点。
  List<TextAnnotation> _localFindMatchesForBlock(
    int blockStart,
    int blockLength,
  ) {
    final matches = widget.documentController.findMatches;
    if (matches.isEmpty || blockLength == 0) return const [];
    final blockEnd = blockStart + blockLength;
    final currentIndex = widget.documentController.findCurrentIndex;
    final result = <TextAnnotation>[];
    for (var i = 0; i < matches.length; i++) {
      final m = matches[i];
      if (m.end <= blockStart || m.start >= blockEnd) continue;
      final localStart = (m.start - blockStart).clamp(0, blockLength);
      final localEnd = (m.end - blockStart).clamp(0, blockLength);
      if (localEnd <= localStart) continue;
      result.add(
        TextAnnotation(
          start: localStart,
          end: localEnd,
          background: i == currentIndex
              ? const Color(0xFFE89B00).withValues(alpha: 0.65)
              : const Color(0xFFF5C518).withValues(alpha: 0.30),
        ),
      );
    }
    return result;
  }

  void _syncFindHighlights() {
    final blockStart = widget.documentController.blockStart(widget.blockIndex);
    final annotations = _localFindMatchesForBlock(
      blockStart,
      widget.block.text.length,
    );
    _updating = true;
    _textController.setFindHighlights(annotations);
    _updating = false;
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = EditorTypography.bodyText(
      widget.style,
      Theme.of(context),
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
    final gridLineMode = widget.style.gridLineMode;
    final content = Stack(
      children: [
        if (gridLineMode != GridLineMode.none)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: TextGridLinePainter(
                  mode: gridLineMode,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.22),
                  drawTopLine: widget.drawTopGridLine,
                  text: widget.block.text,
                  style: textStyle,
                  textDirection: textDirection,
                  textScaler: textScaler,
                  layoutFor: layoutFor,
                ),
              ),
            ),
          ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _BlockHighlightPainter(
                text: widget.block.text,
                style: textStyle,
                highlights: _localHighlightsForBlock(
                  blockStart,
                  widget.block.text.length,
                ),
                textDirection: textDirection,
                textScaler: textScaler,
                layoutFor: layoutFor,
              ),
            ),
          ),
        ),
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
            cursorColor: EditorCaret.color(Theme.of(context).colorScheme),
            cursorWidth: EditorCaret.width,
            cursorRadius: EditorCaret.radius,
            cursorHeight: EditorCaret.heightFor(widget.style.fontSize),
            inputFormatters: widget.style.firstLineIndent
                ? const [_AutoIndentFormatter()]
                : null,
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
      // 仍可聚焦它，焦点移过去后该段恢复全不透明。content 含网格线层，故网格
      // 线随文字一并淡化（视觉一致：网格线属于段落而非全局辅助）。
      //
      // 关键：专注模式开启时 Opacity 包裹必须始终存在、只切换 opacity 数值，而非
      // 按 dimmed 条件增删。否则淡化↔恢复会让此 Focus 的子树类型在 Opacity↔Stack
      // 间切换，Flutter 因 runtimeType 不同无法 reconcile，遂销毁并重建整个 content
      // 子树——含 TextField 内部的 EditableText 及其持有光标闪烁计时器的 State。block
      // 的 FocusNode 归 _LargeTextBlockFieldState 所有、跨重建保留，hasFocus 仍为
      // 真，但新生的 EditableText 收不到焦点「变化」事件（焦点在它诞生前已设置），
      // 光标闪烁永不启动 → 专注模式下点击段落只激活却不显光标，需移位再点一次才
      // 出现，方向键跨段同样丢光标。
      //
      // 守卫挂在 style.focusMode（模式级，开启后基本恒定）而非 dimmed（每次光标
      // 跨段都变）：专注模式内子树恒为 Opacity，dimmed 仅改数值、不重建子树；专注
      // 模式关闭则根本不包 Opacity，默认渲染与改前一致、零额外 RenderObject。模式
      // 偶发切换时一次性重建无妨（光标下次交互即恢复）。
      child: widget.style.focusMode
          ? Opacity(opacity: widget.dimmed ? 0.28 : 1.0, child: content)
          : content,
    );
  }
}

final class _BlockGeometryRegistry {
  final Map<int, _LargeTextBlockFieldState> _states = {};

  /// 目标段未渲染时由 editor state 实现：滚动使其被 ListView 构建，再重试聚焦。
  /// 为 null（未注册）时退化为原静默行为。
  void Function(int index, LoreLargeTextController controller)?
  ensureBlockVisibleAndFocus;

  Iterable<int> get indices => _states.keys;

  /// 目标段 state（未渲染时为 null）。供 editor state 在滚动后重试聚焦使用。
  _LargeTextBlockFieldState? stateFor(int index) => _states[index];

  /// 当前持有键盘焦点的段 index；无聚焦段时为 null。用于判定跨段滚动方向。
  int? get focusedBlockIndex {
    for (final entry in _states.entries) {
      if (entry.value.hasFocus) {
        return entry.key;
      }
    }
    return null;
  }

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
    if (state != null) {
      state.focusAt(controller.selection);
      return;
    }
    // 目标段未渲染（在视口 + cacheExtent 之外）：交给 editor state 滚动使其被
    // 构建，再 post-frame 重试聚焦。避免「model selection 已移走但焦点没跟上」
    // 的脱节——否则后续按键会基于错误的 blockIndex 解读 selection。
    ensureBlockVisibleAndFocus?.call(index, controller);
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
