import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:flutter/material.dart';

import 'history_diff_mode.dart';

/// 历史版本 diff 视图：字符级差异着色，响应式布局（宽屏并排 split + 同步滚动；
/// 窄屏 unified 内联）。顶部显示净增删字数摘要。
///
/// diff 由 `diff_match_patch` 计算（字符级，cleanupSemantic 归并），渲染为
/// TextSpan：新增绿底、删除红底删除线、未变正常。
class HistoryDiffView extends StatefulWidget {
  const HistoryDiffView({
    required this.oldText,
    required this.newText,
    this.mode = DiffViewMode.inline,
    super.key,
  });

  final String oldText;
  final String newText;
  final DiffViewMode mode;

  @override
  State<HistoryDiffView> createState() => _HistoryDiffViewState();
}

class _HistoryDiffViewState extends State<HistoryDiffView> {
  late final List<Diff> _diffs;
  late final int _added;
  late final int _removed;
  late final ScrollController _leftController;
  late final ScrollController _rightController;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _diffs = diff(widget.oldText, widget.newText);
    cleanupSemantic(_diffs);
    var added = 0;
    var removed = 0;
    for (final d in _diffs) {
      if (d.operation > 0) {
        added += d.text.length;
      } else if (d.operation < 0) {
        removed += d.text.length;
      }
    }
    _added = added;
    _removed = removed;
    _leftController = ScrollController();
    _rightController = ScrollController();
    _leftController.addListener(() => _sync(_rightController, _leftController));
    _rightController.addListener(
      () => _sync(_leftController, _rightController),
    );
  }

  void _sync(ScrollController target, ScrollController source) {
    if (_syncing || !target.hasClients || !source.hasClients) return;
    _syncing = true;
    target.jumpTo(source.offset.clamp(0, target.position.maxScrollExtent));
    _syncing = false;
  }

  @override
  void dispose() {
    _leftController.dispose();
    _rightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Wrap(
            spacing: 14,
            children: [
              Text(
                '+$_added',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: _insertColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '−$_removed',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: _deleteColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (widget.mode == DiffViewMode.split &&
                  constraints.maxWidth >= 640) {
                return _split(theme, cs);
              }
              return _unified(theme, cs);
            },
          ),
        ),
      ],
    );
  }

  Widget _unified(ThemeData theme, ColorScheme cs) {
    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: SelectableText.rich(
          TextSpan(
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.7),
            children: _diffs
                .map(
                  (d) => TextSpan(text: d.text, style: _spanStyle(d.operation)),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _split(ThemeData theme, ColorScheme cs) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _pane(
            label: '旧版本',
            controller: _leftController,
            cs: cs,
            theme: theme,
            span: TextSpan(
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.7),
              children: _diffs
                  .where((d) => d.operation <= 0)
                  .map(
                    (d) =>
                        TextSpan(text: d.text, style: _spanStyle(d.operation)),
                  )
                  .toList(),
            ),
          ),
        ),
        VerticalDivider(width: 1, color: cs.outlineVariant),
        Expanded(
          child: _pane(
            label: '新版本',
            controller: _rightController,
            cs: cs,
            theme: theme,
            span: TextSpan(
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.7),
              children: _diffs
                  .where((d) => d.operation >= 0)
                  .map(
                    (d) =>
                        TextSpan(text: d.text, style: _spanStyle(d.operation)),
                  )
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _pane({
    required String label,
    required ScrollController controller,
    required TextSpan span,
    required ColorScheme cs,
    required ThemeData theme,
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
              padding: const EdgeInsets.all(12),
              child: SelectableText.rich(span),
            ),
          ),
        ),
      ],
    );
  }

  // operation: 1 = INSERT（增）, -1 = DELETE（删）, 0 = EQUAL（未变）。
  TextStyle? _spanStyle(int operation) {
    if (operation == 0) return null;
    if (operation > 0) {
      return TextStyle(backgroundColor: _insertBg, color: _insertColor);
    }
    return TextStyle(
      backgroundColor: _deleteBg,
      color: _deleteColor,
      decoration: TextDecoration.lineThrough,
      decorationColor: _deleteColor,
    );
  }

  // diff 着色：绿增红删（跨主题一致惯例），背景低 alpha 适应明暗模式。
  static const _insertColor = Color(0xFF1B7F3A);
  static const _deleteColor = Color(0xFFC2364B);
  static Color get _insertBg => _insertColor.withValues(alpha: 0.16);
  static Color get _deleteBg => _deleteColor.withValues(alpha: 0.16);
}
