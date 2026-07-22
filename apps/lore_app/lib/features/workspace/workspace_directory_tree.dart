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

  /// 目录树竖向滚动控制器，用于把选中条目滚入视口（reveal）。
  final ScrollController _scrollController = ScrollController();

  /// 异步祖先加载期间暂存的待揭示路径；可见列表每次重建都尝试消费它（见
  /// [_consumePendingReveal]），保证祖先加载完成后仍能滚入视口。
  String? _pendingRevealPath;

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
      // 控制器/书库切换：旧 pending 揭示路径对新树无意义，必须清掉，否则新树
      // 首帧加载后会把同名残留路径误滚入视口。
      _pendingRevealPath = null;
      _loadInitialTree();
      return;
    }
    if (oldWidget.reloadToken != widget.reloadToken) {
      _refreshLoadedTree();
    }
    if (oldWidget.selectedPath != widget.selectedPath) {
      // 选中变化（点 Tab / 点目录树文件 / 新建等）→ 下一帧把选中条目滚入视口。
      // reveal 只滚动、不写选中态，无回环。
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
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
    _consumePendingReveal();
  }

  /// 选中条目变化时（[didUpdateWidget] 触发）：把它滚入视口；若被折叠的祖先
  /// 遮挡，先逐级展开祖先再滚（VSCode 风格）。
  void _revealSelected() {
    if (!mounted) {
      return;
    }
    final path = widget.selectedPath;
    if (path == null || path.isEmpty) {
      _pendingRevealPath = null;
      return;
    }
    _pendingRevealPath = path;
    setState(() {
      _expandAncestors(path);
      _rebuildVisibleItems();
    });
  }

  /// 展开选中路径的所有真祖先目录（不含自身）并触发其懒加载；已缓存者即时
  /// 可见，未缓存者由 [_loadPath] 完成后的 [_scheduleVisibleRebuild] 经
  /// [_consumePendingReveal] 补滚。
  ///
  /// 注意：[WorkspaceController.setDirectoryExpanded] 会经 session 持久化展开态，
  /// 故 reveal 触发的自动展开会被「记住」——与 VSCode `explorer.autoReveal` 一致
  /// （自动展开的目录下次打开仍是展开的）。这是有意为之。
  void _expandAncestors(String path) {
    final segments = path.split('/');
    if (segments.length <= 1) {
      return; // 根级条目，无真祖先。
    }
    var ancestor = '';
    for (var i = 0; i < segments.length - 1; i++) {
      ancestor = ancestor.isEmpty ? segments[i] : '$ancestor/${segments[i]}';
      if (widget.controller.isDirectoryExpanded(ancestor)) {
        continue;
      }
      widget.controller.setDirectoryExpanded(ancestor, true);
      _loadPath(ancestor, prioritize: true);
    }
  }

  /// reveal 异步收敛的单一收口：每次可见列表重建后，若待揭示路径已可见则安排
  /// 滚动；仍在加载则留待下一次重建重试。路径不存在时永不满，悬挂至下次选中
  /// 变化（或控制器/书库切换的全量重载）时被重置——无害。
  ///
  /// 注意：本方法在 [_rebuildVisibleItems] 末尾被调用，而后者多处处于 setState
  /// 构建期；因此本方法只可调度 post-frame 回调 / 改字段，**绝不可 setState**
  /// （否则触发「build 期 setState」断言）。
  void _consumePendingReveal() {
    final path = _pendingRevealPath;
    if (path == null) {
      return;
    }
    final index = _visibleItems.indexWhere(
      (item) => item.entry?.relativePath == path,
    );
    if (index < 0) {
      return;
    }
    _pendingRevealPath = null;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToVisibleIndex(index),
    );
  }

  /// 把第 [index] 行用最小滚动量移入视口：上方则滚到顶部并留 [_revealContext]
  /// 上下文，下方则滚到底部留上下文，已可见则不滚。固定行高使索引→偏移精确。
  void _scrollToVisibleIndex(int index) {
    if (!mounted || !_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    final rowTop = _treeListTopPadding + index * _treeRowExtent;
    final rowBottom = rowTop + _treeRowExtent;
    final viewport = position.viewportDimension;
    final current = position.pixels;
    double? target;
    if (rowTop < current) {
      target = rowTop - _revealContext;
    } else if (rowBottom > current + viewport) {
      target = rowBottom - viewport + _revealContext;
    }
    if (target == null) {
      return; // 已可见。
    }
    _scrollController.animateTo(
      target.clamp(0.0, position.maxScrollExtent),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
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
    _scrollController.dispose();
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
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(8, _treeListTopPadding, 8, 6),
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

/// 目录树 ListView 顶部内边距；reveal 偏移计算需计入它（见 [_scrollToVisibleIndex]）。
const double _treeListTopPadding = 2;

/// reveal 时露出的上下文像素：被揭示项不贴边，留一点呼吸空间（VSCode 体感）。
const double _revealContext = 8;
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
