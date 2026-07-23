import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:path/path.dart' as p;

import '../workspace_controller.dart';
import 'quick_open_file_index.dart';
import 'quick_open_matcher.dart';

/// 卡片距视口顶部的留白(VSCode quick open 贴近顶部下拉的体感)。
const double _quickOpenTopPadding = 96;

/// 结果列表最大高度(约 8 行),超出滚动;结果少时随内容收缩。
const double _resultListMaxHeight = 360;

/// 唤起「快速打开」面板(VSCode 风格 Cmd+P):顶部居中的圆角浮动卡片,
/// 输入即模糊匹配工作区所有可打开文件,`↑/↓` 选择、回车打开、`Esc`/点遮罩关闭。
///
/// 卡片装饰复用 `_LorePanel`(`lore_panel_sheet.dart`)的 token,surface 背景 +
/// outlineVariant 边框 + 双层阴影 + `circular(10)`;所有颜色取自 ColorScheme,
/// light/dark/sepia 自动适配。面板为短生命周期 StatefulWidget,内部自管列表与
/// 选中状态,不引入 Riverpod(与 [FindReplaceController] 内联模式一致)。
Future<void> showQuickOpenPanel({
  required BuildContext context,
  required WorkspaceController controller,
  void Function(LibraryFailure)? onFailure,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.transparent,
    builder: (_) =>
        _QuickOpenDialog(controller: controller, onFailure: onFailure),
  );
}

class _QuickOpenDialog extends StatelessWidget {
  const _QuickOpenDialog({required this.controller, this.onFailure});

  final WorkspaceController controller;
  final void Function(LibraryFailure)? onFailure;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final maxWidth = (media.width - 64).clamp(320.0, 600.0);
    final maxHeight = (media.height * 0.55).clamp(220.0, 460.0);
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 32,
          vertical: _quickOpenTopPadding,
        ),
        child: _QuickOpenCard(
          controller: controller,
          onFailure: onFailure,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
        ),
      ),
    );
  }
}

class _QuickOpenCard extends StatefulWidget {
  const _QuickOpenCard({
    required this.controller,
    required this.maxWidth,
    required this.maxHeight,
    this.onFailure,
  });

  final WorkspaceController controller;
  final double maxWidth;
  final double maxHeight;
  final void Function(LibraryFailure)? onFailure;

  @override
  State<_QuickOpenCard> createState() => _QuickOpenCardState();
}

/// 一条带得分的匹配结果,用于排序与高亮。
class _ScoredEntry {
  const _ScoredEntry(this.entry, this.match);
  final LibraryEntry entry;
  final QuickOpenMatch match;
}

class _QuickOpenCardState extends State<_QuickOpenCard> {
  final TextEditingController _queryController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _activeRowKey = GlobalKey();

  List<LibraryEntry> _all = const [];
  bool _loading = true;
  String _query = '';
  List<_ScoredEntry> _results = const [];
  int _selected = 0;
  bool _submitting = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadFiles() async {
    List<LibraryEntry> files;
    try {
      files = await collectOpenableFiles(widget.controller);
    } catch (_) {
      files = const [];
    }
    if (!mounted) return;
    setState(() {
      _all = files;
      _loading = false;
    });
    _recompute('');
  }

  void _onChanged(String value) {
    if (value == _query) return;
    _query = value;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), _recompute);
  }

  void _recompute([String? query]) {
    final q = (query ?? _query).trim();
    final List<_ScoredEntry> scored;
    if (q.isEmpty) {
      scored = const [];
    } else {
      scored = [];
      for (final entry in _all) {
        final m = fuzzyMatch(q, displayName(entry));
        if (m != null) scored.add(_ScoredEntry(entry, m));
      }
      scored.sort((a, b) {
        final byScore = b.match.score.compareTo(a.match.score);
        if (byScore != 0) return byScore;
        return displayName(a.entry).compareTo(displayName(b.entry));
      });
    }
    setState(() {
      _results = scored;
      _selected = 0;
    });
  }

  void _moveBy(int delta) {
    if (_results.isEmpty) return;
    final next = _selected + delta;
    if (next < 0 || next >= _results.length) return;
    setState(() => _selected = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _activeRowKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: const Duration(milliseconds: 80),
        );
      }
    });
  }

  Future<void> _openSelected() async {
    if (_submitting) return;
    if (_selected < 0 || _selected >= _results.length) return;
    _submitting = true;
    final entry = _results[_selected].entry;
    final controller = widget.controller;
    final void Function(LibraryFailure)? onFailure = widget.onFailure;
    try {
      await controller.openPath(entry.relativePath);
    } on LibraryOperationException catch (error) {
      if (mounted && onFailure != null) onFailure(error.failure);
    } catch (_) {
      // 磁盘 IO 等非预期异常(如文件已被外部移动/删除):吞掉,
      // 避免冒泡到 FlutterError.onError,统一走失败回调。
      if (mounted && onFailure != null) {
        onFailure(
          const LibraryFailure(
            code: LibraryFailureCode.io,
            message: '文件无法打开,可能已被移动或删除。',
          ),
        );
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _moveBy(-1),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _moveBy(1),
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Container(
        constraints: BoxConstraints(
          maxWidth: widget.maxWidth,
          maxHeight: widget.maxHeight,
        ),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colors.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSearchField(theme, colors),
                Divider(height: 1, thickness: 1, color: colors.outlineVariant),
                _buildBody(theme, colors),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField(ThemeData theme, ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: TextField(
        controller: _queryController,
        focusNode: _focusNode,
        autofocus: true,
        style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isCollapsed: true,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          hintText: '按名称搜索文件…',
          hintStyle: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 13,
            color: colors.onSurfaceVariant,
          ),
        ),
        onChanged: _onChanged,
        onSubmitted: (_) => _openSelected(),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, ColorScheme colors) {
    if (_loading) {
      return const SizedBox(
        height: 72,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      final idle = _query.trim().isEmpty;
      return SizedBox(
        height: 72,
        child: Center(
          child: Text(
            idle ? '输入以搜索文件…' : '无匹配文件',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _resultListMaxHeight),
      child: ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        itemCount: _results.length,
        itemBuilder: (context, index) {
          final scored = _results[index];
          return _ResultRow(
            key: index == _selected ? _activeRowKey : null,
            entry: scored.entry,
            matchedIndices: scored.match.matchedIndices,
            selected: index == _selected,
            theme: theme,
            onTap: () {
              setState(() => _selected = index);
              _openSelected();
            },
          );
        },
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.entry,
    required this.matchedIndices,
    required this.selected,
    required this.theme,
    required this.onTap,
    super.key,
  });

  final LibraryEntry entry;
  final List<int> matchedIndices;
  final bool selected;
  final ThemeData theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = theme.colorScheme;
    final name = displayName(entry);
    final dir = p.dirname(entry.relativePath);
    final isMarkdown = entry.type == LibraryEntryType.markdownFile;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Material(
        color: selected
            ? colors.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: colors.onSurface.withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Icon(
                  isMarkdown
                      ? Icons.article_outlined
                      : Icons.description_outlined,
                  size: 16,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 9),
                Expanded(child: _buildHighlightedName(name, colors)),
                if (dir.isNotEmpty && dir != '.') ...[
                  const SizedBox(width: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(
                      dir,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHighlightedName(String name, ColorScheme colors) {
    final base = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w500,
    );
    final hit = base?.copyWith(
      color: colors.primary,
      fontWeight: FontWeight.w700,
    );
    final hits = matchedIndices.toSet();
    final spans = <TextSpan>[];
    for (var i = 0; i < name.length; i++) {
      spans.add(TextSpan(text: name[i], style: hits.contains(i) ? hit : base));
    }
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(children: spans, style: base),
    );
  }
}
