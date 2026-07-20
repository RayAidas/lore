import 'dart:async';
import 'dart:collection';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:lore_domain/lore_domain.dart';

import 'library_entry_icons.dart';
import 'workspace_controller.dart';

/// 目录树右键/长按上下文菜单回调：携带目标条目与触发的全局坐标。
typedef ContextMenuCallback =
    void Function(LibraryEntry entry, Offset globalPosition);

/// 侧栏目录树：扁平化并虚拟渲染可见条目，目录可展开懒加载。
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
  final Map<String, List<LibraryEntry>> _childrenByPath = {};
  final Map<String, Object> _loadErrors = {};
  final Map<String, int> _requestVersions = {};
  final Map<String, _DirectoryLoadRequest> _loadsByPath = {};
  final Queue<_DirectoryLoadRequest> _loadQueue = Queue();
  final List<_VisibleTreeItem> _visibleItems = [];
  int _generation = 0;
  int _runningLoadCount = 0;
  bool _visibleRebuildScheduled = false;

  @override
  void initState() {
    super.initState();
    _loadInitialTree();
  }

  @override
  void didUpdateWidget(covariant WorkspaceDirectory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.relativePath != widget.relativePath) {
      _generation += 1;
      _childrenByPath.clear();
      _loadErrors.clear();
      _requestVersions.clear();
      _loadsByPath.clear();
      _loadQueue.clear();
      _visibleItems.clear();
      _loadInitialTree();
      return;
    }
    if (oldWidget.reloadToken != widget.reloadToken) {
      _refreshLoadedTree();
    }
  }

  void _loadInitialTree() {
    _loadPath(widget.relativePath, prioritize: true);
    for (final path in widget.controller.expandedDirectoryPaths) {
      if (_isWithinRoot(path)) {
        _loadPath(path);
      }
    }
  }

  void _refreshLoadedTree() {
    final paths = <String>{
      widget.relativePath,
      ...widget.controller.expandedDirectoryPaths.where(_isWithinRoot),
    };
    final stalePaths = <String>{
      ..._childrenByPath.keys,
      ..._loadErrors.keys,
      ..._loadsByPath.keys,
    }.difference(paths);
    for (final path in stalePaths) {
      _invalidatePath(path);
    }
    for (final path in paths) {
      _loadPath(path, force: true, prioritize: path == widget.relativePath);
    }
  }

  void _invalidatePath(String path) {
    _childrenByPath.remove(path);
    _loadErrors.remove(path);
    _requestVersions[path] = (_requestVersions[path] ?? 0) + 1;
    _loadsByPath.remove(path);
  }

  bool _isWithinRoot(String path) {
    final root = widget.relativePath;
    return root.isEmpty || path == root || path.startsWith('$root/');
  }

  void _loadPath(String path, {bool force = false, bool prioritize = false}) {
    if (!force && _childrenByPath.containsKey(path)) {
      return;
    }
    final existing = _loadsByPath[path];
    if (existing != null) {
      if (prioritize && !existing.started && _loadQueue.remove(existing)) {
        _loadQueue.addFirst(existing);
      }
      if (force && existing.started) {
        existing.refreshAfterCompletion = true;
      }
      return;
    }
    final generation = _generation;
    final requestVersion = (_requestVersions[path] ?? 0) + 1;
    _requestVersions[path] = requestVersion;
    final request = _DirectoryLoadRequest(
      path: path,
      generation: generation,
      version: requestVersion,
    );
    _loadsByPath[path] = request;
    if (prioritize) {
      _loadQueue.addFirst(request);
    } else {
      _loadQueue.addLast(request);
    }
    _drainLoadQueue();
  }

  void _drainLoadQueue() {
    if (!mounted) {
      _loadQueue.clear();
      return;
    }
    while (_runningLoadCount < _maximumConcurrentDirectoryLoads &&
        _loadQueue.isNotEmpty) {
      final request = _loadQueue.removeFirst();
      if (_loadsByPath[request.path] != request) {
        continue;
      }
      request.started = true;
      _runningLoadCount += 1;
      _startLoad(request);
    }
  }

  void _startLoad(_DirectoryLoadRequest request) {
    unawaited(
      widget.controller
          .listChildren(relativePath: request.path)
          .then((entries) {
            if (!_isCurrentRequest(request)) {
              return;
            }
            _childrenByPath[request.path] = entries;
            _loadErrors.remove(request.path);
            _scheduleVisibleRebuild();
            _loadExpandedChildren(entries);
          })
          .catchError((Object error) {
            if (!_isCurrentRequest(request)) {
              return;
            }
            _loadErrors[request.path] = error;
            _scheduleVisibleRebuild();
          })
          .whenComplete(() {
            _runningLoadCount -= 1;
            if (_loadsByPath[request.path] == request) {
              _loadsByPath.remove(request.path);
              if (request.refreshAfterCompletion) {
                _loadPath(request.path, force: true, prioritize: true);
              }
            }
            _drainLoadQueue();
          }),
    );
  }

  bool _isCurrentRequest(_DirectoryLoadRequest request) {
    return mounted &&
        request.generation == _generation &&
        _requestVersions[request.path] == request.version &&
        _loadsByPath[request.path] == request;
  }

  void _scheduleVisibleRebuild() {
    if (_visibleRebuildScheduled) {
      return;
    }
    _visibleRebuildScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _visibleRebuildScheduled = false;
      if (mounted) {
        setState(_rebuildVisibleItems);
      }
    });
  }

  void _loadExpandedChildren(List<LibraryEntry> entries) {
    for (final entry in entries) {
      if (entry.isDirectory &&
          widget.controller.isDirectoryExpanded(entry.relativePath)) {
        _loadPath(entry.relativePath);
      }
    }
  }

  void _rebuildVisibleItems() {
    _visibleItems.clear();
    _appendVisibleChildren(widget.relativePath, widget.depth);
  }

  void _appendVisibleChildren(String path, int depth) {
    if (_loadErrors.containsKey(path)) {
      _visibleItems.add(_VisibleTreeItem.error(path: path, depth: depth));
    }
    final entries = _childrenByPath[path];
    if (entries == null) {
      return;
    }
    for (final entry in entries) {
      _visibleItems.add(_VisibleTreeItem.entry(entry: entry, depth: depth));
      if (entry.isDirectory &&
          widget.controller.isDirectoryExpanded(entry.relativePath)) {
        _appendVisibleChildren(entry.relativePath, depth + 1);
      }
    }
  }

  void _toggleExpanded(LibraryEntry entry) {
    final expanded = !widget.controller.isDirectoryExpanded(entry.relativePath);
    widget.controller.setDirectoryExpanded(entry.relativePath, expanded);
    setState(_rebuildVisibleItems);
    if (expanded) {
      _loadPath(entry.relativePath, prioritize: true);
    }
    widget.onSelected(entry);
  }

  void _retryPath(String path) {
    setState(() {
      _loadErrors.remove(path);
      _rebuildVisibleItems();
    });
    _loadPath(path, force: true, prioritize: true);
  }

  @override
  void dispose() {
    _loadQueue.clear();
    _loadsByPath.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rootEntries = _childrenByPath[widget.relativePath];
    if (rootEntries == null) {
      if (_loadErrors.containsKey(widget.relativePath)) {
        return TextButton(
          onPressed: () => _retryPath(widget.relativePath),
          child: const Text('目录加载失败，点击重试'),
        );
      }
      return widget.relativePath.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : const SizedBox.shrink();
    }
    if (rootEntries.isEmpty && !_loadErrors.containsKey(widget.relativePath)) {
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
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
      physics: const ClampingScrollPhysics(),
      itemExtent: _treeRowExtent,
      itemCount: _visibleItems.length,
      itemBuilder: (context, index) {
        final item = _visibleItems[index];
        final errorPath = item.errorPath;
        if (errorPath != null) {
          return SizedBox(
            height: _treeRowExtent,
            child: TextButton(
              onPressed: () => _retryPath(errorPath),
              child: const Text('目录刷新失败，点击重试'),
            ),
          );
        }
        final entry = item.entry!;
        final expanded = entry.isDirectory
            ? widget.controller.isDirectoryExpanded(entry.relativePath)
            : null;
        return _TreeRow(
          key: ValueKey(entry.relativePath),
          entry: entry,
          selected: widget.selectedPath == entry.relativePath,
          depth: item.depth,
          expanded: expanded,
          disclosure: expanded == null
              ? const SizedBox(width: _treeDisclosureWidth)
              : AnimatedRotation(
                  turns: expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOut,
                  child: const Icon(Icons.chevron_right_rounded, size: 17),
                ),
          icon: expanded == true ? Icons.folder_open_outlined : entry.entryIcon,
          onTap: entry.isDirectory
              ? () => _toggleExpanded(entry)
              : () => widget.onSelected(entry),
          onContextMenu: widget.onContextMenu,
          statsLabel: widget.controller.statsLabelFor(entry),
        );
      },
    );
  }
}

final class _DirectoryLoadRequest {
  _DirectoryLoadRequest({
    required this.path,
    required this.generation,
    required this.version,
  });

  final String path;
  final int generation;
  final int version;
  bool started = false;
  bool refreshAfterCompletion = false;
}

final class _VisibleTreeItem {
  const _VisibleTreeItem.entry({required this.entry, required this.depth})
    : errorPath = null;

  const _VisibleTreeItem.error({required String path, required this.depth})
    : entry = null,
      errorPath = path;

  final LibraryEntry? entry;
  final String? errorPath;
  final int depth;
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
    super.key,
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
  // 桌面端 InkWell 会把鼠标右键 up 误当 onTap 触发，导致右键弹菜单的同时
  // 误打开条目。这里在 [Listener.onPointerDown] 阶段按按钮同步置位/复位：
  // 指针事件在手势竞技场裁决之前同步分发，保证右键标志一定先于可能误触的
  // onTap 就绪（比依赖 onSecondaryTapDown 的时序更稳，不随 Flutter 版本漂移）。
  bool _secondaryArmed = false;

  void _handlePointerDown(PointerDownEvent event) {
    if (event.buttons == kSecondaryButton) {
      _secondaryArmed = true;
    } else if (event.buttons == kPrimaryButton) {
      // 右键标志若未被误触的 onTap 消费，不能跨到下一次左键点击，否则
      // 右键后第一次左键会被吞掉。下一次主键 down 时复位。
      _secondaryArmed = false;
    }
  }

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
      child: Listener(
        onPointerDown: _handlePointerDown,
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
              onSecondaryTapUp: onContextMenu == null
                  ? null
                  : (details) => onContextMenu(entry, details.globalPosition),
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
      ),
    );
  }
}

const double _treeHorizontalPadding = 4;
const double _treeIndent = 17;
const double _treeDisclosureWidth = 18;
const double _treeRowHeight = 30;
const double _treeRowExtent = _treeRowHeight + 2;
const int _maximumConcurrentDirectoryLoads = 6;

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
