import 'package:flutter/material.dart';
import 'package:lore_domain/lore_domain.dart';

import 'library_entry_icons.dart';
import 'workspace_controller.dart';

/// 侧栏目录树：递归列出书库条目，目录可展开懒加载。
final class WorkspaceDirectory extends StatefulWidget {
  const WorkspaceDirectory({
    required this.controller,
    required this.relativePath,
    required this.selectedPath,
    required this.reloadToken,
    required this.onSelected,
    super.key,
  });

  final WorkspaceController controller;
  final String relativePath;
  final String? selectedPath;
  final int reloadToken;
  final ValueChanged<LibraryEntry> onSelected;

  @override
  State<WorkspaceDirectory> createState() => _WorkspaceDirectoryState();
}

final class _WorkspaceDirectoryState extends State<WorkspaceDirectory> {
  late Future<List<LibraryEntry>> _entries;

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
        if (snapshot.connectionState != ConnectionState.done) {
          return widget.relativePath.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : const LinearProgressIndicator();
        }
        if (snapshot.hasError) {
          return TextButton(
            onPressed: () => setState(_reload),
            child: const Text('目录加载失败，点击重试'),
          );
        }
        final entries = snapshot.data ?? const <LibraryEntry>[];
        if (entries.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(widget.relativePath.isEmpty ? '书库为空' : '文件夹为空'),
          );
        }
        final children = entries.map((entry) {
          if (entry.isDirectory) {
            return _WorkspaceDirectoryTile(
              entry: entry,
              controller: widget.controller,
              selectedPath: widget.selectedPath,
              reloadToken: widget.reloadToken,
              onSelected: widget.onSelected,
            );
          }
          return ListTile(
            dense: true,
            minVerticalPadding: 0,
            leading: Icon(
              entry.entryIcon,
              size: 18,
              color: entry.entryIconColor(context),
            ),
            title: Text(
              entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            selected: widget.selectedPath == entry.relativePath,
            onTap: () => widget.onSelected(entry),
          );
        }).toList();
        return widget.relativePath.isEmpty
            ? ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
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
  });

  final LibraryEntry entry;
  final WorkspaceController controller;
  final String? selectedPath;
  final int reloadToken;
  final ValueChanged<LibraryEntry> onSelected;

  @override
  State<_WorkspaceDirectoryTile> createState() =>
      _WorkspaceDirectoryTileState();
}

final class _WorkspaceDirectoryTileState
    extends State<_WorkspaceDirectoryTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selectedPath == widget.entry.relativePath;
    final colorScheme = Theme.of(context).colorScheme;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Material(
          color: selected
              ? colorScheme.primaryContainer.withValues(alpha: 0.5)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: ExpansionTile(
            dense: true,
            minTileHeight: 38,
            initiallyExpanded: _expanded,
            iconColor: colorScheme.onSurfaceVariant,
            collapsedIconColor: colorScheme.onSurfaceVariant,
            leading: Icon(
              _expanded && widget.entry.semanticKind == null
                  ? Icons.folder_open_outlined
                  : widget.entry.entryIcon,
              size: 18,
              color: widget.entry.entryIconColor(context),
            ),
            title: Text(
              widget.entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            tilePadding: const EdgeInsets.symmetric(horizontal: 8),
            childrenPadding: const EdgeInsets.only(left: 12),
            onExpansionChanged: (expanded) {
              setState(() => _expanded = expanded);
              widget.onSelected(widget.entry);
            },
            children: _expanded
                ? [
                    WorkspaceDirectory(
                      controller: widget.controller,
                      relativePath: widget.entry.relativePath,
                      selectedPath: widget.selectedPath,
                      reloadToken: widget.reloadToken,
                      onSelected: widget.onSelected,
                    ),
                  ]
                : const [],
          ),
        ),
      ),
    );
  }
}
