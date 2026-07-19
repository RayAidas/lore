import 'package:flutter/material.dart';
import 'package:lore_domain/lore_domain.dart';

import 'library_entry_icons.dart';
import 'workspace_controller.dart';

/// 目录树右键/长按上下文菜单回调：携带目标条目与触发的全局坐标。
typedef ContextMenuCallback =
    void Function(LibraryEntry entry, Offset globalPosition);

/// 侧栏目录树：递归列出书库条目，目录可展开懒加载。
final class WorkspaceDirectory extends StatefulWidget {
  const WorkspaceDirectory({
    required this.controller,
    required this.relativePath,
    required this.selectedPath,
    required this.reloadToken,
    required this.onSelected,
    this.onContextMenu,
    this.depth = 0,
    super.key,
  });

  final WorkspaceController controller;
  final String relativePath;
  final String? selectedPath;
  final int reloadToken;
  final ValueChanged<LibraryEntry> onSelected;
  final ContextMenuCallback? onContextMenu;
  final int depth;

  @override
  State<WorkspaceDirectory> createState() => _WorkspaceDirectoryState();
}

final class _WorkspaceDirectoryState extends State<WorkspaceDirectory> {
  late Future<List<LibraryEntry>> _entries;
  List<LibraryEntry>? _cachedEntries;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant WorkspaceDirectory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.relativePath != widget.relativePath ||
        oldWidget.reloadToken != widget.reloadToken) {
      _reload();
    }
  }

  void _reload() {
    _entries = widget.controller.listChildren(
      relativePath: widget.relativePath,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LibraryEntry>>(
      future: _entries,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          _cachedEntries = snapshot.data;
        }
        final entries = snapshot.data ?? _cachedEntries;
        if (entries == null &&
            snapshot.connectionState != ConnectionState.done) {
          return widget.relativePath.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                  padding: EdgeInsets.only(
                    left:
                        _treeHorizontalPadding +
                        (widget.depth * _treeIndent) +
                        _treeDisclosureWidth,
                    right: _treeHorizontalPadding,
                    top: 4,
                    bottom: 4,
                  ),
                  child: const LinearProgressIndicator(minHeight: 2),
                );
        }
        if (entries == null) {
          return TextButton(
            onPressed: () => setState(_reload),
            child: const Text('目录加载失败，点击重试'),
          );
        }
        if (entries.isEmpty && !snapshot.hasError) {
          // 仅书库根为空时给出提示；展开的空文件夹保持静默，不再占位。
          if (widget.relativePath.isNotEmpty) {
            return const SizedBox.shrink();
          }
          return Padding(
            padding: EdgeInsets.fromLTRB(
              _treeHorizontalPadding +
                  (widget.depth * _treeIndent) +
                  _treeDisclosureWidth,
              10,
              _treeHorizontalPadding,
              10,
            ),
            child: Text(
              '书库为空',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        final children = <Widget>[
          if (snapshot.hasError)
            TextButton(
              onPressed: () => setState(_reload),
              child: const Text('目录刷新失败，点击重试'),
            ),
          ...entries.map((entry) {
            if (entry.isDirectory) {
              return _WorkspaceDirectoryTile(
                key: ValueKey(entry.relativePath),
                entry: entry,
                controller: widget.controller,
                selectedPath: widget.selectedPath,
                reloadToken: widget.reloadToken,
                onSelected: widget.onSelected,
                onContextMenu: widget.onContextMenu,
                depth: widget.depth,
                statsLabel: widget.controller.statsLabelFor(entry),
              );
            }
            return _WorkspaceFileTile(
              key: ValueKey(entry.relativePath),
              entry: entry,
              selected: widget.selectedPath == entry.relativePath,
              depth: widget.depth,
              onTap: () => widget.onSelected(entry),
              onContextMenu: widget.onContextMenu,
              statsLabel: widget.controller.statsLabelFor(entry),
            );
          }),
        ];
        return widget.relativePath.isEmpty
            ? ListView(
                padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
                physics: const ClampingScrollPhysics(),
                children: children,
              )
            : Column(mainAxisSize: MainAxisSize.min, children: children);
      },
    );
  }
}

final class _WorkspaceDirectoryTile extends StatefulWidget {
  const _WorkspaceDirectoryTile({
    required this.entry,
    required this.controller,
    required this.selectedPath,
    required this.reloadToken,
    required this.onSelected,
    this.onContextMenu,
    required this.depth,
    this.statsLabel,
    super.key,
  });

  final LibraryEntry entry;
  final WorkspaceController controller;
  final String? selectedPath;
  final int reloadToken;
  final ValueChanged<LibraryEntry> onSelected;
  final ContextMenuCallback? onContextMenu;
  final int depth;
  final String? statsLabel;

  @override
  State<_WorkspaceDirectoryTile> createState() =>
      _WorkspaceDirectoryTileState();
}

final class _WorkspaceDirectoryTileState
    extends State<_WorkspaceDirectoryTile> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.controller.isDirectoryExpanded(
      widget.entry.relativePath,
    );
  }

  @override
  void didUpdateWidget(covariant _WorkspaceDirectoryTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.entry.relativePath != widget.entry.relativePath) {
      _expanded = widget.controller.isDirectoryExpanded(
        widget.entry.relativePath,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selectedPath == widget.entry.relativePath;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TreeRow(
          entry: widget.entry,
          selected: selected,
          depth: widget.depth,
          expanded: _expanded,
          disclosure: AnimatedRotation(
            turns: _expanded ? 0.25 : 0,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            child: const Icon(Icons.chevron_right_rounded, size: 17),
          ),
          icon: _expanded ? Icons.folder_open_outlined : Icons.folder_outlined,
          onTap: _toggleExpanded,
          onContextMenu: widget.onContextMenu,
          statsLabel: widget.statsLabel,
        ),
        if (_expanded)
          WorkspaceDirectory(
            controller: widget.controller,
            relativePath: widget.entry.relativePath,
            selectedPath: widget.selectedPath,
            reloadToken: widget.reloadToken,
            onSelected: widget.onSelected,
            onContextMenu: widget.onContextMenu,
            depth: widget.depth + 1,
          ),
      ],
    );
  }

  void _toggleExpanded() {
    final expanded = !_expanded;
    setState(() => _expanded = expanded);
    widget.controller.setDirectoryExpanded(widget.entry.relativePath, expanded);
    widget.onSelected(widget.entry);
  }
}

final class _WorkspaceFileTile extends StatelessWidget {
  const _WorkspaceFileTile({
    required this.entry,
    required this.selected,
    required this.depth,
    required this.onTap,
    this.onContextMenu,
    this.statsLabel,
    super.key,
  });

  final LibraryEntry entry;
  final bool selected;
  final int depth;
  final VoidCallback onTap;
  final ContextMenuCallback? onContextMenu;
  final String? statsLabel;

  @override
  Widget build(BuildContext context) {
    return _TreeRow(
      entry: entry,
      selected: selected,
      depth: depth,
      disclosure: const SizedBox(width: _treeDisclosureWidth),
      icon: entry.entryIcon,
      onTap: onTap,
      onContextMenu: onContextMenu,
      statsLabel: statsLabel,
    );
  }
}

final class _TreeRow extends StatefulWidget {
  const _TreeRow({
    required this.entry,
    required this.selected,
    required this.depth,
    required this.disclosure,
    required this.icon,
    required this.onTap,
    this.onContextMenu,
    this.expanded,
    this.statsLabel,
  });

  final LibraryEntry entry;
  final bool selected;
  final int depth;
  final Widget disclosure;
  final IconData icon;
  final VoidCallback onTap;
  final ContextMenuCallback? onContextMenu;
  final bool? expanded;
  final String? statsLabel;

  @override
  State<_TreeRow> createState() => _TreeRowState();
}

final class _TreeRowState extends State<_TreeRow> {
  // 右键 down 时置位，防止 InkWell 桌面在鼠标事件上偶发把右键 up 也当
  // onTap 触发，导致右键弹菜单的同时误打开条目。
  bool _secondaryArmed = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final selected = widget.selected;
    final depth = widget.depth;
    final disclosure = widget.disclosure;
    final icon = widget.icon;
    final onTap = widget.onTap;
    final onContextMenu = widget.onContextMenu;
    final expanded = widget.expanded;
    final statsLabel = widget.statsLabel;
    final colorScheme = Theme.of(context).colorScheme;
    final rowColor = selected
        ? colorScheme.primaryContainer.withValues(alpha: 0.52)
        : Colors.transparent;
    final displayName = _treeDisplayName(entry);
    final textStyle =
        Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface.withValues(alpha: selected ? 1 : 0.88),
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ) ??
        const TextStyle();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Semantics(
        container: true,
        button: true,
        selected: selected,
        expanded: expanded,
        onExpand: expanded == false ? onTap : null,
        onCollapse: expanded == true ? onTap : null,
        child: Material(
          color: rowColor,
          borderRadius: BorderRadius.circular(7),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              if (!_secondaryArmed) {
                onTap();
              }
              _secondaryArmed = false;
            },
            onSecondaryTapDown: (_) {
              _secondaryArmed = true;
            },
            onSecondaryTapUp: onContextMenu == null
                ? null
                : (details) => onContextMenu(entry, details.globalPosition),
            onSecondaryTapCancel: () {
              _secondaryArmed = false;
            },
            onLongPress: onContextMenu == null
                ? null
                : () {
                    final box = context.findRenderObject() as RenderBox?;
                    if (box != null) {
                      onContextMenu(entry, box.localToGlobal(Offset.zero));
                    }
                  },
            hoverColor: colorScheme.onSurface.withValues(alpha: 0.045),
            focusColor: colorScheme.primary.withValues(alpha: 0.08),
            splashColor: colorScheme.primary.withValues(alpha: 0.08),
            child: SizedBox(
              height: _treeRowHeight,
              child: Padding(
                padding: EdgeInsets.only(
                  left: _treeHorizontalPadding + (depth * _treeIndent),
                  right: 10,
                ),
                child: Row(
                  children: [
                    IconTheme(
                      data: IconThemeData(
                        size: 17,
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.78,
                        ),
                      ),
                      child: SizedBox(
                        width: _treeDisclosureWidth,
                        child: Center(child: disclosure),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      icon,
                      size: 18,
                      color: entry
                          .entryIconColor(context)
                          .withValues(alpha: selected ? 1 : 0.84),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: _OverflowTooltip(
                        message: displayName,
                        style: textStyle,
                        child: Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textStyle,
                        ),
                      ),
                    ),
                    if (statsLabel != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          statsLabel,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const double _treeHorizontalPadding = 4;
const double _treeIndent = 17;
const double _treeDisclosureWidth = 18;
const double _treeRowHeight = 30;

const _txtExtension = '.txt';

/// 目录树展示名：文本文件隐藏 `.txt` 后缀（大小写不敏感，与存储层分类一致），
/// 其余条目保留原文件名；纯 `.txt` 这类会剥离为空的名字则原样返回。
String _treeDisplayName(LibraryEntry entry) {
  final name = entry.name;
  if (entry.type == LibraryEntryType.textFile &&
      name.length > _txtExtension.length &&
      name.toLowerCase().endsWith(_txtExtension)) {
    return name.substring(0, name.length - _txtExtension.length);
  }
  return name;
}

/// 仅当子 [Text] 在可用宽度内放不下（会被省略号截断）时才显示 [Tooltip]。
///
/// 目录树行宽通常足以完整显示文件名，此时 hover 不应弹出重复提示；仅当
/// 名字超长被截断时，才用 tooltip 暴露完整名（与 VSCode 文件树行为一致）。
class _OverflowTooltip extends StatelessWidget {
  const _OverflowTooltip({
    required this.message,
    required this.style,
    required this.child,
  });

  final String message;
  final TextStyle style;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: message, style: style),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout();
        final overflow = painter.width > constraints.maxWidth;
        painter.dispose();
        return overflow
            ? Tooltip(
                message: message,
                waitDuration: const Duration(milliseconds: 700),
                child: child,
              )
            : child;
      },
    );
  }
}
