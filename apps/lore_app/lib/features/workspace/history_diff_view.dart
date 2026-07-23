import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:flutter/material.dart';
import 'package:lore_editor/lore_editor.dart';

import 'history_diff_mode.dart';

/// 历史对比净增删字数（字符级）：供对比工具行展示。与 [HistoryDiffView] 内部 diff
/// 同源——cleanupSemantic 后按 operation 累加字符数（INSERT 计增、DELETE 计减）。
({int added, int removed}) diffCharStats(String oldText, String newText) {
  final diffs = diff(oldText, newText);
  cleanupSemantic(diffs);
  var added = 0;
  var removed = 0;
  for (final d in diffs) {
    if (d.operation > 0) {
      added += d.text.length;
    } else if (d.operation < 0) {
      removed += d.text.length;
    }
  }
  return (added: added, removed: removed);
}

/// diff 着色：增绿 / 删红。饱和度足够、不依赖 ColorScheme 派生色，亮暗主题通用。
const Color diffInsertColor = Color(0xFF1B7F3A);
const Color diffDeleteColor = Color(0xFFC2364B);

/// 历史版本 diff 视图：字符级差异着色，响应式布局（宽屏并排 split + 同步滚动；
/// 窄屏 unified 内联）。净增删字数摘要（[diffCharStats]）由宿主对比工具行展示，
/// 本视图只负责正文着色。
///
/// 排版与几何完全复用编辑器同源原语（[EditorTypography] / [buildAnnotationSpans]）：
/// 正文 / 标题字号字体行高、内容宽度居中、52 阅读内边距、段首缩进、段间距、标题块
/// 几何——全部来自单一来源，与编辑器 / `ChapterTitleBar` 按构造保持一致，杜绝漂移。
///
/// diff 着色（红删删除线 / 绿增）走与 highlight 同构的 [TextAnnotation] 模型：每段
/// 的 diff 流映射成段落内局部标注区间，由 [buildAnnotationSpans] 拼成 `TextSpan` 树，
/// 经只读的 `SelectableText.rich` 渲染（构造上不可编辑）。章节标题作为独立首块，
/// 套编辑器标题排版；标题变更时 unified 对标题做字符级 diff。
class HistoryDiffView extends StatefulWidget {
  const HistoryDiffView({
    required this.oldText,
    required this.newText,
    this.oldTitle,
    this.newTitle,
    this.mode = DiffViewMode.inline,
    this.style = const EditorStyle.defaults(),
    super.key,
  });

  /// 旧侧（历史快照）正文。章节文档应为去掉标题首行后的纯正文。
  final String oldText;

  /// 新侧（当前磁盘）正文。章节文档应为去掉标题首行后的纯正文。
  final String newText;

  /// 旧侧章节标题行（`第N章 副标题`，不含 Markdown `#`）。非章节文档传 null：
  /// 此时 diff 全文、不渲染标题块。
  final String? oldTitle;

  /// 新侧章节标题行。语义同 [oldTitle]；两者都非空才渲染标题块。
  final String? newTitle;

  final DiffViewMode mode;

  /// 编辑器排版参数：diff 视觉跟随编辑器（字体 / 字号 / 行高 / 宽度 / 缩进 / 段距 /
  /// 标题字号）。
  final EditorStyle style;

  @override
  State<HistoryDiffView> createState() => _HistoryDiffViewState();
}

/// 一个段落：纯正文文本 + 段内局部标注（offset 相对 [text]）+ [markerOp]。
typedef _Paragraph = ({
  String text,
  List<TextAnnotation> annotations,
  // 仅对空段（空行）有意义：终结该空段的换行所属操作（1 INSERT / -1 DELETE）。
  // 非空段恒为 0。用来给「加/删空行」整行着色。
  int markerOp,
});

class _HistoryDiffViewState extends State<HistoryDiffView> {
  // diff / 计数 / 标题 diff 随 oldText/newText/oldTitle/newTitle 变化重算
  //（见 didUpdateWidget），故非 final。
  late List<Diff> _diffs;
  List<Diff>? _titleDiffs;
  late final ScrollController _unifiedController;
  late final ScrollController _leftController;
  late final ScrollController _rightController;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _computeDiff();
    _unifiedController = ScrollController();
    _leftController = ScrollController();
    _rightController = ScrollController();
    _leftController.addListener(() => _sync(_rightController, _leftController));
    _rightController.addListener(
      () => _sync(_leftController, _rightController),
    );
  }

  @override
  void didUpdateWidget(covariant HistoryDiffView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 点版本列表里另一个版本时，本组件在树中位置不变 → State 复用、initState 不再
    // 跑。文本/标题变化须在此重算，否则视图停在第一个版本。
    if (oldWidget.oldText != widget.oldText ||
        oldWidget.newText != widget.newText ||
        oldWidget.oldTitle != widget.oldTitle ||
        oldWidget.newTitle != widget.newTitle) {
      _computeDiff();
      // 切到另一个版本后回到顶部：State 复用会保留上个版本的滚动位置，而新内容
      // 可能更短（offset 被夹紧）或更长，回到顶部避免用户看到「上一版的下半截」。
      _jumpToTopNextFrame();
    }
  }

  void _jumpToTopNextFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final c in [_unifiedController, _leftController, _rightController]) {
        if (c.hasClients) c.jumpTo(0);
      }
    });
  }

  /// 由 oldText/newText/oldTitle/newTitle 派生 diff、增删计数、标题 diff。
  void _computeDiff() {
    _diffs = diff(widget.oldText, widget.newText);
    cleanupSemantic(_diffs);
    // 标题 diff：仅当两侧标题都存在且不同时才计算（相同时渲染中性单行）。
    _titleDiffs =
        (widget.oldTitle != null &&
            widget.newTitle != null &&
            widget.oldTitle != widget.newTitle)
        ? (() {
            final t = diff(widget.oldTitle!, widget.newTitle!);
            cleanupSemantic(t);
            return t;
          })()
        : null;
  }

  void _sync(ScrollController target, ScrollController source) {
    if (_syncing || !target.hasClients || !source.hasClients) return;
    _syncing = true;
    target.jumpTo(source.offset.clamp(0, target.position.maxScrollExtent));
    _syncing = false;
  }

  @override
  void dispose() {
    _unifiedController.dispose();
    _leftController.dispose();
    _rightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final base = EditorTypography.bodyText(widget.style, theme);
    final titleStyle = EditorTypography.titleText(widget.style, theme);
    // 网格线：与编辑器同口径（onSurface alpha 0.22），按段落内文本布局逐行画底线。
    final grid = (
      mode: widget.style.gridLineMode,
      color: cs.onSurface.withValues(alpha: 0.22),
      dir: Directionality.of(context),
      scaler: MediaQuery.textScalerOf(context),
    );
    // 净增删摘要（+N −N）已上移到对比工具行（见 DocumentPane._buildDiff），
    // 本视图只负责 diff 正文着色。
    return LayoutBuilder(
      builder: (context, constraints) {
        if (widget.mode == DiffViewMode.split && constraints.maxWidth >= 640) {
          return _split(theme, cs, base, titleStyle, grid);
        }
        return _unified(base, titleStyle, grid);
      },
    );
  }

  /// 把字符级 diff 流按 `\n` 切成段落；每段产出纯文本 + 段内局部标注（EQUAL 无标注、
  /// INSERT 绿底绿字、DELETE 红底红字删除线）。段间空行保留为空文本段落；末尾换行
  /// 产生的末空段丢弃。
  ///
  /// **空行增删的可见性**：本应用里「空行」常带首行缩进全角空格 `　　`（回车自动补），
  /// 故「空白行」= 空串或仅含空白字符（`trim().isEmpty`，含全角空格）。当差异是
  /// 「加/删一个空白行」时：
  /// - 纯空行（仅 `\n`）：由终结它的换行的操作记入 [markerOp]。
  /// - 仅空白字符行（如 `　　`）：由其内容的单一 operation 记入 [markerOp]。
  /// 渲染时整行着色（绿增红删），与 VSCode 给增删空行整行上色同义。未变化或 operation
  /// 混杂的空白行 markerOp 为 0、按普通段渲染。
  ///
  /// **已知边界**：纯尾部换行（如 `abc`→`abc\n`）产生的末空段仍被丢弃、不显示
  /// （尾部空白属噪声），但其字符数计入顶部摘要。仅段**中间**的空行变化会着色显示。
  List<_Paragraph> _paragraphs(List<Diff> diffs) {
    final paragraphs = <_Paragraph>[];
    var text = StringBuffer();
    var annotations = <TextAnnotation>[];
    // 段落正文是否来自单一 operation（用于判定「整行增/删」）：仅记首个非空片段的
    // operation，其后出现不同 operation 则置 mixed。
    var hasContent = false;
    var firstOp = 0;
    var contentMixed = false;

    void close(int terminatingOp) {
      // 「空白行」判定用 trim()：空串或仅含空白（含全角空格 　，即首行缩进留下的
      // 空段）都算。空白行若是整行增/删，渲染时整行着色（markerOp），否则按普通段。
      final s = text.toString();
      final blankLike = s.trim().isEmpty;
      final markerOp = !blankLike
          ? 0
          : s.isEmpty
          ? terminatingOp // 纯空行：由终结它的换行的操作决定
          : (!contentMixed && firstOp != 0
                ? firstOp
                : 0); // 仅空白字符行：由其内容 operation 决定
      paragraphs.add((text: s, annotations: annotations, markerOp: markerOp));
      text = StringBuffer();
      annotations = <TextAnnotation>[];
      hasContent = false;
      firstOp = 0;
      contentMixed = false;
    }

    for (final d in diffs) {
      final parts = d.text.split('\n');
      for (var i = 0; i < parts.length; i++) {
        if (parts[i].isNotEmpty) {
          if (!hasContent) {
            hasContent = true;
            firstOp = d.operation;
          } else if (d.operation != firstOp) {
            contentMixed = true;
          }
          final start = text.length;
          text.write(parts[i]);
          final ann = _annotationFor(d.operation, start, text.length);
          if (ann != null) annotations.add(ann);
        }
        if (i < parts.length - 1) {
          close(d.operation);
        }
      }
    }
    if (text.isNotEmpty || annotations.isNotEmpty) {
      close(0);
    }
    return paragraphs;
  }

  /// operation → 段内局部标注。EQUAL 返回 null（不着色）。
  TextAnnotation? _annotationFor(int operation, int start, int end) {
    if (operation == 0) return null;
    if (operation > 0) {
      return TextAnnotation(
        start: start,
        end: end,
        background: _insertBg,
        color: _insertColor,
      );
    }
    return TextAnnotation(
      start: start,
      end: end,
      background: _deleteBg,
      color: _deleteColor,
      strikethrough: true,
    );
  }

  /// 段落块列表：每段一个 [_DiffParagraph]（段底间距与编辑器同口径）。空段渲染为
  /// 一行高的空白，匹配编辑器空段。
  ///
  /// 注意：**不再额外补段首缩进**。编辑器的 firstLineIndent 是把两个全角空格
  /// 【写入正文文本】（`_AutoIndentFormatter` / `prependSilently`），不是渲染装饰；
  /// 快照正文已自带缩进字符，这里按原文渲染即可，否则会叠成 4 字缩进。
  List<Widget> _paragraphBlocks(
    List<Diff> diffs,
    TextStyle? base,
    _GridStyle grid,
  ) {
    final gap = widget.style.paragraphSpacing * widget.style.fontSize;
    final blankLine = widget.style.fontSize * widget.style.lineHeight;
    final blocks = <Widget>[];
    // 网格线 drawTopLine：首个非空段不画顶部线（与编辑器首段一致），其后每段都画，
    // 使段间距上下都有线、网格连续——否则每段顶部缺一条，整体网格「少了很多」。
    var seenNonEmpty = false;
    for (final p in _paragraphs(diffs)) {
      final Widget content;
      if (p.markerOp != 0) {
        // 空白行被整行增/删（纯空行，或仅含空白字符——如首行缩进留下的 　　 段）：
        // 整行着色（绿增红删），不按字符渲染，使变化清晰可见。
        final tint = p.markerOp > 0 ? _insertBg : _deleteBg;
        content = ColoredBox(
          color: tint,
          child: SizedBox(height: blankLine, width: double.infinity),
        );
        seenNonEmpty = true; // 着色块占一行，后续段照常画顶部网格线
      } else if (p.text.isEmpty) {
        // 未变化的纯空行。
        content = SizedBox(height: blankLine);
      } else {
        content = _DiffParagraph(
          text: p.text,
          base: base,
          annotations: p.annotations,
          grid: grid,
          drawTopLine: seenNonEmpty,
        );
        seenNonEmpty = true;
      }
      blocks.add(
        Padding(
          padding: EdgeInsets.only(bottom: gap),
          child: content,
        ),
      );
    }
    return blocks;
  }

  /// unified 标题块：两侧标题都存在才渲染。相同→中性单行；不同→对标题做字符级
  /// diff（红删绿增，继承标题字号 / 字重）。
  TextSpan? _unifiedTitleSpan(TextStyle titleStyle) {
    final oldT = widget.oldTitle;
    final newT = widget.newTitle;
    if (oldT == null || newT == null) return null;
    final diffs = _titleDiffs;
    if (diffs == null) {
      return TextSpan(style: titleStyle, text: oldT);
    }
    // 标题无换行 → 单段；其交错文本 + 增删标注由 buildAnnotationSpans 拼成 span 树。
    final paragraphs = _paragraphs(diffs);
    final p = paragraphs.isEmpty
        ? (text: '', annotations: const <TextAnnotation>[], markerOp: 0)
        : paragraphs.first;
    return TextSpan(
      style: titleStyle,
      children: buildAnnotationSpans(p.text, p.annotations),
    );
  }

  /// split 单侧标题块：该侧标题存在才渲染（中性，差异由左右两列本身呈现）。
  TextSpan? _sideTitleSpan(String? title, TextStyle titleStyle) {
    if (title == null) return null;
    return TextSpan(style: titleStyle, text: title);
  }

  /// 内容列：编辑器同源几何（contentFrame 居中宽度 + 52 阅读内边距）；可选标题块
  /// （标题排版 + titleTopInset/titleBottomSpacing）在顶，其下为正文段落块。横向
  /// 内边距统一为 [EditorTypography.readingInset]，使标题与正文左缘对齐。
  Widget _contentColumn({
    required List<Diff> bodyDiffs,
    required TextStyle? base,
    required _GridStyle grid,
    TextSpan? titleSpan,
  }) {
    final children = <Widget>[];
    if (titleSpan != null) {
      children.add(
        Padding(
          padding: EdgeInsets.only(
            top: EditorTypography.titleTopInset,
            bottom: widget.style.titleBottomSpacing,
          ),
          child: SelectableText.rich(titleSpan),
        ),
      );
    } else {
      // 无标题：与编辑器非章节文档同款顶部留白。
      children.add(SizedBox(height: EditorTypography.titleTopInset));
    }
    children.addAll(_paragraphBlocks(bodyDiffs, base, grid));
    return EditorTypography.contentFrame(
      widget.style,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: EditorTypography.readingInset,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  Widget _unified(TextStyle? base, TextStyle titleStyle, _GridStyle grid) {
    // 显式 controller：避免依赖 PrimaryScrollController（State 复用重排时位置可能
    // 瞬时不稳，导致 Scrollbar hover 报 "no ScrollPosition attached"）。
    return Scrollbar(
      controller: _unifiedController,
      child: SingleChildScrollView(
        controller: _unifiedController,
        padding: const EdgeInsets.only(bottom: 32),
        child: _contentColumn(
          bodyDiffs: _diffs,
          base: base,
          grid: grid,
          titleSpan: _unifiedTitleSpan(titleStyle),
        ),
      ),
    );
  }

  Widget _split(
    ThemeData theme,
    ColorScheme cs,
    TextStyle? base,
    TextStyle titleStyle,
    _GridStyle grid,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _pane(
            label: '旧版本',
            controller: _leftController,
            cs: cs,
            theme: theme,
            base: base,
            grid: grid,
            // 旧侧：EQUAL + DELETE（删除以红底删除线标出）。
            diffs: _diffs.where((d) => d.operation <= 0).toList(),
            titleSpan: _sideTitleSpan(widget.oldTitle, titleStyle),
          ),
        ),
        VerticalDivider(width: 1, color: cs.outlineVariant),
        Expanded(
          child: _pane(
            label: '新版本',
            controller: _rightController,
            cs: cs,
            theme: theme,
            base: base,
            grid: grid,
            // 新侧：EQUAL + INSERT（新增以绿底标出）。
            diffs: _diffs.where((d) => d.operation >= 0).toList(),
            titleSpan: _sideTitleSpan(widget.newTitle, titleStyle),
          ),
        ),
      ],
    );
  }

  Widget _pane({
    required String label,
    required ScrollController controller,
    required List<Diff> diffs,
    required TextStyle? base,
    required ColorScheme cs,
    required ThemeData theme,
    required _GridStyle grid,
    TextSpan? titleSpan,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          color: cs.surfaceContainerLow,
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Scrollbar(
            controller: controller,
            child: SingleChildScrollView(
              controller: controller,
              padding: const EdgeInsets.only(bottom: 32),
              child: _contentColumn(
                bodyDiffs: diffs,
                base: base,
                grid: grid,
                titleSpan: titleSpan,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // diff 着色：绿增红删（跨主题一致惯例），背景低 alpha 适应明暗模式。
  static const _insertColor = diffInsertColor;
  static const _deleteColor = diffDeleteColor;
  static Color get _insertBg => _insertColor.withValues(alpha: 0.16);
  static Color get _deleteBg => _deleteColor.withValues(alpha: 0.16);
}

/// 段落网格线渲染所需的布局上下文：模式 / 颜色 / 文字方向 / 文本缩放。
typedef _GridStyle = ({
  GridLineMode mode,
  Color color,
  TextDirection dir,
  TextScaler scaler,
});

/// diff 单个正文段落：只读着色文本（[buildAnnotationSpans]）+ 可选网格线
/// （[TextGridLinePainter]，与编辑器同源 painter）。
///
/// 网格线需按段落文本的 layout 取行高，故持有自己的 [TextPainter]（paint 时按当前
/// 宽度 layout、复用同一实例、dispose 时释放，避免每次 paint 构造泄漏）。字形层的
/// span 树只设颜色 / 背景不影响排版，故 flat `TextSpan(text, base)` 的行序与
/// `SelectableText.rich` 渲染完全一致，网格线与文字行底对齐。
final class _DiffParagraph extends StatefulWidget {
  const _DiffParagraph({
    required this.text,
    required this.base,
    required this.annotations,
    required this.grid,
    required this.drawTopLine,
  });

  final String text;
  final TextStyle? base;
  final List<TextAnnotation> annotations;
  final _GridStyle grid;

  /// 是否在段落顶部补一条网格线（首段为 false，其后为 true），与编辑器 drawTopLine
  /// 同口径，使段间距上下都有线、网格连续。
  final bool drawTopLine;

  @override
  State<_DiffParagraph> createState() => _DiffParagraphState();
}

final class _DiffParagraphState extends State<_DiffParagraph> {
  final TextPainter _layout = TextPainter();

  @override
  void dispose() {
    _layout.dispose();
    super.dispose();
  }

  TextPainter _layoutFor(double width) {
    _layout
      ..text = TextSpan(text: widget.text, style: widget.base)
      ..textDirection = widget.grid.dir
      ..textScaler = widget.grid.scaler
      ..layout(maxWidth: width);
    return _layout;
  }

  @override
  Widget build(BuildContext context) {
    final text = SelectableText.rich(
      TextSpan(
        style: widget.base,
        children: buildAnnotationSpans(widget.text, widget.annotations),
      ),
    );
    if (widget.grid.mode == GridLineMode.none) return text;
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: TextGridLinePainter(
                mode: widget.grid.mode,
                color: widget.grid.color,
                drawTopLine: widget.drawTopLine,
                text: widget.text,
                style: widget.base,
                textDirection: widget.grid.dir,
                textScaler: widget.grid.scaler,
                layoutFor: _layoutFor,
              ),
            ),
          ),
        ),
        text,
      ],
    );
  }
}
