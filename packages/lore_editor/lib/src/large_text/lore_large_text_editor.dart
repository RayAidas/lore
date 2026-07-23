import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:lore_domain/lore_domain.dart';

import '../annotation/grid_line_painter.dart';
import '../annotation/text_annotation.dart';
import '../editor_style.dart';
import '../editor_typography.dart';
import 'lore_large_text_controller.dart';
import 'pasted_text_normalizer.dart';

part 'lore_large_text_block_field.dart';
part 'lore_large_text_editing.dart';
part 'lore_large_text_painters.dart';

/// 段首两字缩进，与导入解析、加载兜底共用 [paragraphIndent]（lore_domain）
/// 这一单一真值，避免各包各自定义 `'　　'` 导致漂移。
const String _paragraphIndent = paragraphIndent;

/// Tab 缩进：单全角空格（U+3000），即中文排版「一个字」的宽度，也是
/// [_paragraphIndent] 的基本单位。按 Tab 在光标处插入一个；选区非空时替换选区。
const String _tabIndent = '　';

final class LoreLargeTextEditor extends StatefulWidget {
  const LoreLargeTextEditor({
    required this.controller,
    required this.scrollController,
    this.style = const EditorStyle.defaults(),
    this.autofocus = false,
    this.topPadding = 42,
    this.focusNode,
    this.indentFirstParagraph = false,
    this.header,
    this.onContextMenu,
    super.key,
  });

  final LoreLargeTextController controller;
  final ScrollController scrollController;
  final EditorStyle style;
  final bool autofocus;

  /// 滚动视口顶部的固定式（随正文滚动）首块。挂载为 `CustomScrollView` 的首个
  /// sliver，因此会随正文一起滚动——供章节文档把标题塞进编辑器滚动区使用。
  /// 传入 `null` 时视口只有正文块。
  final Widget? header;

  /// 文本区域收到右键(macOS)或长按(Android)时触发,传入全局坐标。由上层
  /// (document_pane)组装上下文菜单(高亮色块/复制/取消高亮)。为 null 时禁用菜单。
  final void Function(Offset globalPosition)? onContextMenu;

  /// 是否为正文首段自动补两字缩进（与回车开新段的 [_AutoIndentFormatter] 一致）。
  /// 章节文档（标题与正文分离）开启：挂载时若首段为空就注入 `　　`，使「点进
  /// 首段」或「标题回车进入」时缩进已就位。仅在 [EditorStyle.firstLineIndent]
  /// 开启时生效。
  final bool indentFirstParagraph;

  /// 列表顶部的垂直留白（底部固定 42）。章节文档在上方挂标题栏时，传入较小
  /// 值（如 0），让标题与正文的间距由标题栏自身的底 padding 统一控制，
  /// 避免两段留白叠加。
  final double topPadding;

  /// 外部聚焦入口：当此节点获得焦点时，把焦点转交给首个段落块并把光标置于
  /// 正文开头。供章节标题栏按回车后「跳到正文」使用。
  final FocusNode? focusNode;

  @override
  State<LoreLargeTextEditor> createState() => _LoreLargeTextEditorState();
}

final class _LoreLargeTextEditorState extends State<LoreLargeTextEditor> {
  final _blockRegistry = _BlockGeometryRegistry();
  int? _pointerSelectionAnchor;
  var _globalSelectionDrag = false;
  late int _observedBlocksRevision;
  int _observedRevealSeq = 0;
  bool _transferringExternalFocus = false;
  Timer? _longPressTimer;
  Offset? _longPressStartPosition;

  /// 段首两字缩进，与 [_AutoIndentFormatter._indent] 共用 [_paragraphIndent]。
  static const String _indent = _paragraphIndent;

  @override
  void initState() {
    super.initState();
    _observedBlocksRevision = widget.controller.blocksRevision;
    _observedRevealSeq = widget.controller.revealSeq;
    widget.controller.addListener(_handleControllerChanged);
    widget.focusNode?.addListener(_handleExternalFocus);
    _blockRegistry.ensureBlockVisibleAndFocus = _ensureBlockVisibleAndFocus;
    // 章节正文首段挂载即补缩进：使「点进首段」「标题回车进入」时缩进已就位。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _ensureFirstParagraphIndent();
      }
    });
  }

  @override
  void didUpdateWidget(covariant LoreLargeTextEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_handleExternalFocus);
      widget.focusNode?.addListener(_handleExternalFocus);
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
    _longPressTimer?.cancel();
    widget.controller.removeListener(_handleControllerChanged);
    widget.focusNode?.removeListener(_handleExternalFocus);
    _blockRegistry.ensureBlockVisibleAndFocus = null;
    super.dispose();
  }

  /// 外部 [FocusNode] 自身成为主焦点时，把焦点转交给首个段落块并把光标置于
  /// 正文开头。用于章节标题栏按回车后跳入正文。
  ///
  /// 关键：用 [FocusNode.hasPrimaryFocus] 而非 `hasFocus` 守卫——后者在任意
  /// 后代（如首个段落块自动聚焦）获焦时也为真，会在每次挂载时误触发并把光标
  /// 重置到开头。仅当外部节点**自身**为主焦点（即被 [FocusNode.requestFocus]
  /// 显式请求）时才转交。block 0 获得主焦点后本节点自动降为祖先，无需手动
  /// unfocus。
  void _handleExternalFocus() {
    final node = widget.focusNode;
    if (node == null || !node.hasPrimaryFocus || _transferringExternalFocus) {
      return;
    }
    _transferringExternalFocus = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _transferringExternalFocus = false;
        return;
      }
      _ensureFirstParagraphIndent();
      // 光标置于首段缩进之后（若有），落到真正可输入位置而非缩进空格里。
      final firstText = widget.controller.blocks.isEmpty
          ? ''
          : widget.controller.blocks.first.text;
      final caretOffset = firstText.startsWith(_indent) ? _indent.length : 0;
      widget.controller.selection = TextSelection.collapsed(
        offset: caretOffset,
      );
      _blockRegistry.focusBlock(0, widget.controller);
      _transferringExternalFocus = false;
    });
  }

  /// 章节正文首段须带两字缩进：挂载时若首段无缩进——空段，或导入/历史章节
  /// 顶格的首段——在开头注入 `　　`。幂等：首段已有缩进则不动。覆盖导入 TXT
  /// 首段常顶格（无缩进）的情况，使每章首段一律带缩进，与回车开新段一致。
  void _ensureFirstParagraphIndent() {
    if (!widget.indentFirstParagraph || !widget.style.firstLineIndent) {
      return;
    }
    final blocks = widget.controller.blocks;
    if (blocks.isEmpty || blocks.first.text.startsWith(_indent)) {
      return;
    }
    widget.controller.prependSilently(_indent);
  }

  void _handleControllerChanged() {
    final blocksChanged =
        _observedBlocksRevision != widget.controller.blocksRevision;
    _observedBlocksRevision = widget.controller.blocksRevision;
    // 查找跳转的 reveal 请求：程序设 selection 不会自动滚动到选区，需显式响应。
    // 用递增序号比较，避免「连续点同一结果（同 offset）」被判为未变化而丢弃。
    final reveal = widget.controller.revealOffset;
    final revealChanged = widget.controller.revealSeq != _observedRevealSeq;
    _observedRevealSeq = widget.controller.revealSeq;
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
      if (revealChanged && reveal != null) {
        // 把匹配所在段落滚入视口并居中（非打字机模式也执行：查找跳转需把目标带入视口）。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || widget.controller.length == 0) {
            return;
          }
          _blockRegistry.focusBlock(
            widget.controller.blockIndexForOffset(reveal),
            widget.controller,
          );
          _scrollCaretToCenter();
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
    final selectionValid = focusMode && widget.controller.selection.isValid;
    final activeBlockIndex = selectionValid
        ? widget.controller.blockIndexForOffset(
            widget.controller.selection.extentOffset,
          )
        : -1;
    return Focus(
      // 把外部 focusNode 挂到焦点树并允许其被请求焦点：章节标题栏按回车后
      // requestFocus 此节点，监听器再把焦点转交给首个段落块。无外部节点时
      // 维持原行为（不可聚焦的纯按键宿主）。
      focusNode: widget.focusNode,
      canRequestFocus: widget.focusNode != null,
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
              child: CustomScrollView(
                controller: widget.scrollController,
                slivers: [
                  if (widget.header case final header?)
                    SliverToBoxAdapter(child: header),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(52, widget.topPadding, 52, 42),
                    sliver: SliverList.builder(
                      itemCount: widget.controller.blocks.length,
                      itemBuilder: (context, index) {
                        final block = widget.controller.blocks[index];
                        final field = _LargeTextBlockField(
                          key: ValueKey(index),
                          block: block,
                          blockIndex: index,
                          documentController: widget.controller,
                          registry: _blockRegistry,
                          globalSelectionDrag: _globalSelectionDrag,
                          style: widget.style,
                          autofocus: widget.autofocus && index == 0,
                          dimmed: selectionValid && index != activeBlockIndex,
                          drawTopGridLine:
                              index > 0 &&
                              widget.controller.blocks[index - 1].hasLineBreak,
                          onFocused: () {},
                        );
                        // 段落末块（hasLineBreak）下方加段间距（字号倍数 × 字号 =
                        // 像素）；同段跨块保持贴合。
                        return block.hasLineBreak
                            ? Padding(
                                padding: EdgeInsets.only(
                                  bottom:
                                      widget.style.paragraphSpacing *
                                      widget.style.fontSize,
                                ),
                                child: field,
                              )
                            : field;
                      },
                    ),
                  ),
                ],
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
    // 右键(macOS):直接弹上下文菜单,不走选区逻辑。
    if (event.buttons == kSecondaryMouseButton) {
      _invokeContextMenu(event.position);
      return;
    }
    if (event.buttons != kPrimaryMouseButton) {
      return;
    }
    // 触摸长按(Android):500ms 计时,位移超 touchSlop 或抬起则取消。绕过手势
    // 竞技场(TextField 已 enableInteractiveSelection:false,无内部长按冲突)。
    if (event.kind == PointerDeviceKind.touch) {
      _longPressStartPosition = event.position;
      _longPressTimer?.cancel();
      _longPressTimer = Timer(const Duration(milliseconds: 500), () {
        final position = _longPressStartPosition;
        if (position != null) {
          _invokeContextMenu(position);
        }
      });
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
    // 长按计时中位移超 touchSlop → 取消(转为正常拖选)。
    final startPosition = _longPressStartPosition;
    if (_longPressTimer != null && startPosition != null) {
      if ((event.position - startPosition).distance > kTouchSlop) {
        _longPressTimer?.cancel();
        _longPressTimer = null;
        _longPressStartPosition = null;
      }
    }
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
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _longPressStartPosition = null;
    _pointerSelectionAnchor = null;
    widget.controller.endSelectionDrag();
    if (_globalSelectionDrag) {
      setState(() => _globalSelectionDrag = false);
    }
  }

  /// 触发上下文菜单回调(右键或长按)。取消任何进行中的长按计时后,把全局
  /// 坐标交给上层组装菜单。
  void _invokeContextMenu(Offset globalPosition) {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _longPressStartPosition = null;
    // 清理可能进行中的选区拖拽:长按触发菜单后若不清,触摸移动会继续改写
    // selection,与菜单打开时捕获的快照 desync。右键路径本就未开启拖拽,无副作用。
    _pointerSelectionAnchor = null;
    widget.controller.endSelectionDrag();
    if (_globalSelectionDrag) {
      setState(() => _globalSelectionDrag = false);
    }
    widget.onContextMenu?.call(globalPosition);
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
    _scrollCaretToCenter();
  }

  /// 把聚焦光标行滚动到视口垂直居中（8px 死区避免微抖）。打字机模式与跨段
  /// 兜底共用：前者由 [_recenterCaretIfNeeded] 守卫后调用，后者由
  /// [_ensureBlockVisibleAndFocus] 在目标段构建后调用。
  void _scrollCaretToCenter() {
    if (!mounted || !widget.scrollController.hasClients) {
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

  /// 向 [targetIndex] 方向粗滚一个视口高度，强制 ListView 把目标段构建出来。
  /// 方向由 targetIndex 与当前聚焦段 [focusedBlockIndex] 比较：目标在焦点段
  /// 下方→向下滚，上方→向上滚；无聚焦段时按 targetIndex 是否大于 0 估算。
  void _scrollToward(int targetIndex) {
    final scrollController = widget.scrollController;
    if (!scrollController.hasClients) {
      return;
    }
    final position = scrollController.position;
    final viewport = position.viewportDimension;
    final focused = _blockRegistry.focusedBlockIndex;
    final downward = focused == null ? targetIndex > 0 : targetIndex > focused;
    final delta = downward ? viewport : -viewport;
    scrollController.jumpTo(
      (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  /// 跨段到未渲染段的兜底：方向性粗滚一个视口（让 ListView 构建目标段），
  /// post-frame 重试聚焦；最多重试 5 次防极端死循环。聚焦成功后再把光标居中。
  /// 用 [depth] 参数计数，避免递归经过 [focusBlock] 时重置。
  void _ensureBlockVisibleAndFocus(
    int index,
    LoreLargeTextController controller, {
    int depth = 0,
  }) {
    if (!mounted || !widget.scrollController.hasClients) {
      return;
    }
    _scrollToward(index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final state = _blockRegistry.stateFor(index);
      if (state != null) {
        state.focusAt(controller.selection);
        // focusAt 后无条件居中：_handleControllerChanged 的 typewriter recenter
        // 在 focusAt 之前跑，用的是原段 caret（原段已被粗滚出视口），会把视口
        // 拉回原段、令目标光标不可见。这里用目标段 caret 覆盖，确保跨段后光标
        // 落在视口内。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _scrollCaretToCenter();
          }
        });
      } else if (depth < 5) {
        _ensureBlockVisibleAndFocus(index, controller, depth: depth + 1);
      }
      // depth 耗尽：放弃聚焦，保持 model selection（用户手动滚动后即恢复）。
    });
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
      // 先折叠外部应用的段间空行，再按当前样式补段首缩进——顺序不能反，
      // 否则缩进会插进 `\n\n` 之间使空行折叠失效。粘贴走文档 controller，
      // 绕过各 block 的 [_AutoIndentFormatter]，故在此显式补一次。
      var pasted = normalizePastedText(text);
      if (widget.style.firstLineIndent) {
        pasted = indentPastedParagraphs(
          pasted,
          _paragraphIndent,
          indentAtStart: pasteInsertsAtParagraphStart(
            widget.controller.text,
            widget.controller.selection.start,
          ),
        );
      }
      widget.controller.replaceSelection(pasted);
    }
  }
}
