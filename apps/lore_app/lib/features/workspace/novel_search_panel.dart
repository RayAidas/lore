import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lore_domain/lore_domain.dart';

import '../preferences/preferences_providers.dart';
import 'novel_search_controller.dart';
import 'workspace_controller.dart';

/// 右栏 Inspector 的「小说搜索」面板：跨章节检索，结果按章节分组、带上下文
/// 片段，点匹配跳转到目标章节。**只搜不替**——替换仍由单文档查找替换（⌘H）承担。
final class NovelSearchPanel extends ConsumerStatefulWidget {
  const NovelSearchPanel({
    required this.controller,
    required this.onSelectMatch,
    super.key,
  });

  final WorkspaceController controller;

  /// 点某条匹配：由页面层桥接到单文档查找（打开章节 + 定位 + 整文高亮）。
  final void Function(ChapterSearchResult result, ChapterMatch match)
  onSelectMatch;

  @override
  ConsumerState<NovelSearchPanel> createState() => _NovelSearchPanelState();
}

final class _NovelSearchPanelState extends ConsumerState<NovelSearchPanel> {
  late final TextEditingController _field;
  late NovelSearchController _search;

  @override
  void initState() {
    super.initState();
    _search = ref.read(
      novelSearchControllerProvider(widget.controller.session),
    );
    // 用查找偏好作默认（与 ⌘F 一致）：大小写/正则跨会话保持。
    final prefs =
        ref.read(appPreferencesProvider).value ?? AppPreferences.defaults();
    _search.applyDefaults(
      matchCase: prefs.findMatchCase,
      useRegex: prefs.findUseRegex,
    );
    _field = TextEditingController(text: _search.pattern);
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // watch（非 read）建立依赖，使 autoDispose provider 在面板存活期间不被回收，
    // 否则 panel 持有的 controller 引用会因 provider 过早 dispose 而失效。
    _search = ref.watch(
      novelSearchControllerProvider(widget.controller.session),
    );
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ListenableBuilder(
      listenable: _search,
      builder: (context, _) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: _buildField(cs),
            ),
            if (_search.pattern.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: _buildSummary(theme, cs),
              ),
            Expanded(child: _buildBody(theme, cs)),
          ],
        );
      },
    );
  }

  Widget _buildField(ColorScheme cs) {
    return TextField(
      controller: _field,
      autofocus: true,
      textInputAction: TextInputAction.search,
      onChanged: _search.setPattern,
      onSubmitted: (_) => _search.runSearch(),
      decoration: InputDecoration(
        isDense: true,
        hintText: '搜索本小说',
        prefixIcon: const Icon(Icons.search, size: 18),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 10,
          horizontal: 10,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _toggle(
              cs,
              active: _search.caseSensitive,
              tooltip: '区分大小写',
              icon: Icons.text_fields,
              onTap: () => _search.setCaseSensitive(!_search.caseSensitive),
            ),
            _toggle(
              cs,
              active: _search.useRegex,
              tooltip: '正则表达式',
              icon: Icons.code,
              onTap: () => _search.setUseRegex(!_search.useRegex),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggle(
    ColorScheme cs, {
    required bool active,
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      iconSize: 18,
      color: active ? cs.primary : null,
      onPressed: onTap,
      icon: Icon(icon),
    );
  }

  Widget _buildSummary(ThemeData theme, ColorScheme cs) {
    final novel = _search.scopeNovel;
    return Row(
      children: [
        Expanded(
          child: Text(
            novel != null ? '范围：${novel.metadata.title}' : '未选择小说',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        if (_search.searching)
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          Text(
            '${_search.totalMatches} 处 / ${_search.chapterHits} 章',
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  Widget _buildBody(ThemeData theme, ColorScheme cs) {
    if (_search.pattern.isEmpty) {
      return const _EmptyHint(icon: Icons.search, message: '输入关键词，搜索本小说全部章节');
    }
    if (_search.searching && _search.results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_search.results.isEmpty) {
      return const _EmptyHint(icon: Icons.search_off, message: '无匹配结果');
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _search.results.length,
      itemBuilder: (context, index) => _ChapterGroup(
        key: ValueKey(_search.results[index].relativePath),
        result: _search.results[index],
        onSelectMatch: widget.onSelectMatch,
      ),
    );
  }
}

final class _ChapterGroup extends StatefulWidget {
  const _ChapterGroup({
    required this.result,
    required this.onSelectMatch,
    super.key,
  });

  final ChapterSearchResult result;
  final void Function(ChapterSearchResult, ChapterMatch) onSelectMatch;

  @override
  State<_ChapterGroup> createState() => _ChapterGroupState();
}

final class _ChapterGroupState extends State<_ChapterGroup> {
  static const _initialVisibleMatches = 10;
  static const _moreMatchesPerStep = 20;
  late int _visibleMatches = _initialVisibleMatches;

  @override
  void didUpdateWidget(covariant _ChapterGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.result.matches.length != widget.result.matches.length) {
      _visibleMatches = _initialVisibleMatches;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.result.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${widget.result.matches.length}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
        for (final m in widget.result.matches.take(_visibleMatches))
          InkWell(
            onTap: () => widget.onSelectMatch(widget.result, m),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 3, 12, 3),
              child: _Snippet(match: m),
            ),
          ),
        if (_visibleMatches < widget.result.matches.length)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(
                () => _visibleMatches = (_visibleMatches + _moreMatchesPerStep)
                    .clamp(0, widget.result.matches.length),
              ),
              child: Text(
                '展开更多（剩余 ${widget.result.matches.length - _visibleMatches} 处）',
              ),
            ),
          ),
      ],
    );
  }
}

/// 上下文片段：匹配段用浅黄背景（与编辑器整文高亮同色系）。
final class _Snippet extends StatelessWidget {
  const _Snippet({required this.match});

  final ChapterMatch match;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final base = theme.textTheme.bodySmall ?? const TextStyle();
    final s = match.snippet;
    final start = match.snippetMatchStart.clamp(0, s.length);
    final end = match.snippetMatchEnd.clamp(start, s.length);
    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: base.copyWith(color: cs.onSurfaceVariant),
        children: [
          TextSpan(text: s.substring(0, start)),
          TextSpan(
            text: s.substring(start, end),
            style: base.copyWith(
              color: cs.onSurface,
              backgroundColor: const Color(0xFFF5C518).withValues(alpha: 0.45),
            ),
          ),
          TextSpan(text: s.substring(end)),
        ],
      ),
    );
  }
}

final class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: cs.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
