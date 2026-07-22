import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:lore_application/lore_application.dart';
import 'package:path/path.dart' as p;

import 'workspace_controller.dart';

/// 标签右键/长按上下文菜单回调：携带目标标签与触发的全局坐标。
typedef TabContextMenuCallback =
    void Function(WorkspaceTab tab, Offset globalPosition);

/// 桌面标签拖动数据，供标签栏和整个工作区窗格共享 drop target。
final class WorkspaceTabDragData {
  const WorkspaceTabDragData({required this.tab, required this.sourceGroupId});

  final WorkspaceTab tab;
  final WorkspaceEditorGroupId sourceGroupId;
}

/// 文档标签条：水平滚动，展示已打开文档，支持激活与关闭。
///
/// 采用现代药丸式（pill）样式：每个标签为全圆角胶囊，随内容撑开（上限
/// [_TabChip.maxWidth]），激活态以中性背景填充，不再使用顶部指示条，靠背景
/// 与文字/图标颜色区分当前页。字重在激活态保持恒定，避免点击时因加粗导致
/// 宽度跳动。文件名超长时省略号截断，hover 整个标签显示完整名。
///
/// 活动标签切换时自动滚入视口（VSCode 风格的最小滚动 reveal）：仅当活动标签
/// 被裁切才滚动，平滑动画，绝不回写选中态。桌面标签行不去虚拟化（标签上限
/// 20、行高 38px，与 VSCode 一致），使任意活动标签的 render object 都已挂载，
/// [Scrollable.ensureVisible] 能精确定位。
final class DocumentTabs extends StatefulWidget {
  const DocumentTabs({
    required this.controller,
    required this.onClose,
    this.groupId = WorkspaceEditorGroupId.primary,
    this.onActivate,
    this.onMove,
    this.onDragStarted,
    this.onDragEnded,
    this.onContextMenu,
    super.key,
  });

  final WorkspaceController controller;
  final Future<void> Function(WorkspaceTab tab) onClose;
  final WorkspaceEditorGroupId groupId;
  final Future<void> Function(WorkspaceTab tab)? onActivate;
  final VoidCallback? onMove;
  final ValueChanged<WorkspaceTabDragData>? onDragStarted;
  final VoidCallback? onDragEnded;
  final TabContextMenuCallback? onContextMenu;

  static const double barHeight = 38;

  @override
  State<DocumentTabs> createState() => _DocumentTabsState();
}

final class _DocumentTabsState extends State<DocumentTabs> {
  /// 桌面标签行的水平滚动控制器（reveal 用 [Scrollable.ensureVisible] 即可，
  /// 此控制器提供稳定句柄，便于测试读取 offset）。
  final ScrollController _scrollController = ScrollController();

  /// 仅挂在当前活动标签所在 cell 上：[Scrollable.ensureVisible] 据此定位。
  final GlobalKey _activeTabKey = GlobalKey();

  /// 上一次感知到的活动路径；与当前值比较决定是否触发 reveal。初始化为挂载时的
  /// 活动路径，避免首帧误触发（VSCode 不在恢复时强制 reveal 活动标签）。
  late String? _lastActivePath;

  WorkspaceController get _controller => widget.controller;

  WorkspaceEditorGroupId get _groupId => widget.groupId;

  @override
  void initState() {
    super.initState();
    _lastActivePath = _controller.activePathForGroup(_groupId);
    _controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant DocumentTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      _controller.addListener(_onControllerChanged);
      _lastActivePath = _controller.activePathForGroup(_groupId);
    } else if (oldWidget.groupId != widget.groupId) {
      // 分组切换：活动路径语义变化，重置基准，不立即 reveal。
      _lastActivePath = _controller.activePathForGroup(_groupId);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _scrollController.dispose();
    super.dispose();
  }

  /// controller 通知时（激活/打开/关闭标签都会改 activePath）：活动路径变化即
  /// 在下一帧把活动标签滚入视口。其余通知（输入、自动保存）做廉价字符串比较
  /// 后立即返回。
  void _onControllerChanged() {
    final active = _controller.activePathForGroup(_groupId);
    if (active == _lastActivePath) {
      return;
    }
    _lastActivePath = active;
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealActiveTab());
  }

  void _revealActiveTab() {
    if (!mounted) {
      return;
    }
    final context = _activeTabKey.currentContext;
    if (context == null) {
      return;
    }
    final tabBox = context.findRenderObject() as RenderBox?;
    if (tabBox == null || !tabBox.attached) {
      return;
    }
    // 标签行 SingleChildScrollView 刚挂载（如空→非空过渡的那一帧）时 position
    // 可能尚未 attach；与目录树一致用 hasClients 守卫，避免取 position 抛 StateError。
    if (!_scrollController.hasClients) {
      return;
    }
    final scrollable = Scrollable.of(context);
    final viewportBox = scrollable.context.findRenderObject() as RenderBox?;
    final position = scrollable.position;
    if (viewportBox == null) {
      return;
    }
    // 最小滚动 reveal：仅在标签被裁切时才滚。比较标签与视口的全局左右边，
    // 算出「刚好把裁切量补齐」的目标偏移。
    final tabLeft = tabBox.localToGlobal(Offset.zero).dx;
    final tabRight = tabLeft + tabBox.size.width;
    final viewportLeft = viewportBox.localToGlobal(Offset.zero).dx;
    final viewportRight = viewportLeft + viewportBox.size.width;
    final current = position.pixels;
    double target;
    if (tabLeft < viewportLeft) {
      target = current - (viewportLeft - tabLeft);
    } else if (tabRight > viewportRight) {
      target = current + (tabRight - viewportRight);
    } else {
      return; // 已完全可见。
    }
    position.animateTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 监听 controller：tabs 增删与 activePath 切换时整体重建，使本组件可脱离
    // 外层 controller 监听独立使用。单 tab 的细粒度刷新仍由下方
    // ListenableBuilder(tab) 负责。
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final colorScheme = Theme.of(context).colorScheme;
        final tabs = _controller.tabsForGroup(_groupId);
        final desktop = switch (Theme.of(context).platform) {
          TargetPlatform.macOS ||
          TargetPlatform.windows ||
          TargetPlatform.linux => true,
          _ => false,
        };
        if (tabs.isEmpty) {
          return DragTarget<WorkspaceTabDragData>(
            onWillAcceptWithDetails: (_) => desktop,
            onAcceptWithDetails: (details) => _moveTab(details.data.tab),
            builder: (context, candidates, _) => ColoredBox(
              color: candidates.isNotEmpty
                  ? colorScheme.primaryContainer.withAlpha(80)
                  : colorScheme.surfaceContainerLowest,
              child: const SizedBox(height: DocumentTabs.barHeight),
            ),
          );
        }
        return ColoredBox(
          color: colorScheme.surfaceContainerLowest,
          child: SizedBox(
            height: DocumentTabs.barHeight,
            child: desktop
                ? _buildDesktopTabs(context, tabs)
                : _buildMobileTabs(tabs),
          ),
        );
      },
    );
  }

  Widget _buildDesktopTabs(BuildContext context, List<WorkspaceTab> tabs) {
    final activePath = _controller.activePathForGroup(_groupId);
    // 去虚拟化：全部标签一次性布局（≤20），保证任意活动标签的 render object
    // 已挂载，[Scrollable.ensureVisible] 可精确定位；与 VSCode 一致。
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < tabs.length; index++)
            _buildDesktopCell(context, tabs[index], index, activePath),
          _buildTrailingDropZone(tabs.length),
        ],
      ),
    );
  }

  /// 桌面单个标签 cell：保留原 `DragTarget` + `Draggable` 落点/拖拽语义。
  /// 活动标签额外挂 [_activeTabKey] 供 reveal 定位。
  Widget _buildDesktopCell(
    BuildContext context,
    WorkspaceTab tab,
    int index,
    String? activePath,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final tabChild = _buildTab(tab);
    final cell = DragTarget<WorkspaceTabDragData>(
      key: ObjectKey(tab),
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) =>
          _moveTab(details.data.tab, index: index),
      builder: (context, candidates, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (candidates.isNotEmpty)
            Container(width: 2, height: 24, color: colorScheme.primary),
          Draggable<WorkspaceTabDragData>(
            data: WorkspaceTabDragData(tab: tab, sourceGroupId: _groupId),
            dragAnchorStrategy: pointerDragAnchorStrategy,
            onDragStarted: () => widget.onDragStarted?.call(
              WorkspaceTabDragData(tab: tab, sourceGroupId: _groupId),
            ),
            onDragEnd: (_) => widget.onDragEnded?.call(),
            feedback: Material(
              color: Colors.transparent,
              child: Opacity(opacity: 0.9, child: _buildTab(tab)),
            ),
            childWhenDragging: Opacity(opacity: 0.35, child: tabChild),
            child: tabChild,
          ),
        ],
      ),
    );
    if (tab.relativePath == activePath) {
      return KeyedSubtree(key: _activeTabKey, child: cell);
    }
    return cell;
  }

  /// 标签行末尾落点：把被拖标签插到最右。
  Widget _buildTrailingDropZone(int trailingIndex) {
    final colorScheme = Theme.of(context).colorScheme;
    return DragTarget<WorkspaceTabDragData>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) =>
          _moveTab(details.data.tab, index: trailingIndex),
      builder: (context, candidates, _) => SizedBox(
        width: candidates.isNotEmpty ? 28 : 12,
        child: candidates.isNotEmpty
            ? Center(
                child: Container(
                  width: 2,
                  height: 24,
                  color: colorScheme.primary,
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildMobileTabs(List<WorkspaceTab> tabs) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      scrollDirection: Axis.horizontal,
      buildDefaultDragHandles: false,
      onReorderItem: (oldIndex, newIndex) => _controller.reorderTab(
        _groupId,
        oldIndex,
        newIndex >= oldIndex ? newIndex + 1 : newIndex,
      ),
      itemCount: tabs.length,
      itemBuilder: (context, index) {
        final tab = tabs[index];
        return KeyedSubtree(
          key: ObjectKey(tab),
          child: _buildTab(
            tab,
            dragHandle: ReorderableDelayedDragStartListener(
              index: index,
              child: const Tooltip(
                message: '拖动排序',
                child: SizedBox(
                  width: 22,
                  height: 24,
                  child: Icon(Icons.drag_indicator_rounded, size: 14),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTab(WorkspaceTab tab, {Widget? dragHandle}) {
    return ListenableBuilder(
      listenable: tab,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: _TabChip(
          tab: tab,
          active: _controller.activePathForGroup(_groupId) == tab.relativePath,
          onTap: () => unawaited(
            widget.onActivate?.call(tab) ?? _controller.activateTab(tab),
          ),
          onClose: () => unawaited(widget.onClose(tab)),
          onContextMenu: widget.onContextMenu,
          dragHandle: dragHandle,
        ),
      ),
    );
  }

  void _moveTab(WorkspaceTab tab, {int? index}) {
    widget.onMove?.call();
    _controller.moveTab(tab, _groupId, index: index);
  }
}

class _TabChip extends StatefulWidget {
  const _TabChip({
    required this.tab,
    required this.active,
    required this.onTap,
    required this.onClose,
    this.onContextMenu,
    this.dragHandle,
  });

  final WorkspaceTab tab;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final TabContextMenuCallback? onContextMenu;
  final Widget? dragHandle;

  /// 标签内容区（图标 + 文件名 + 关闭按钮）的最大宽度（像素）。
  static const double maxWidth = 220;

  static const BorderRadius _borderRadius = BorderRadius.all(
    Radius.circular(7),
  );

  @override
  State<_TabChip> createState() => _TabChipState();
}

class _TabChipState extends State<_TabChip> {
  // 桌面端 InkWell 会把鼠标右键 up 误当 onTap 触发，导致右键弹菜单的同时
  // 误激活标签。这里在 [Listener.onPointerDown] 阶段按按钮同步置位/复位
  // （与目录树 _TreeRowState 一致）：指针事件在手势竞技场裁决之前同步分发，
  // 保证右键标志一定先于可能误触的 onTap 就绪。
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tab = widget.tab;
    final active = widget.active;
    final onContextMenu = widget.onContextMenu;
    final isMarkdown = p.extension(tab.name).toLowerCase() == '.md';
    // 与左侧目录树一致：文本文件隐藏 `.txt` 后缀，Markdown 等保留扩展名。
    final displayName = _tabDisplayName(tab.name);

    return Tooltip(
      message: tab.name,
      excludeFromSemantics: true,
      waitDuration: const Duration(milliseconds: 500),
      child: Semantics(
        label: displayName,
        selected: active,
        button: true,
        child: Listener(
          onPointerDown: _handlePointerDown,
          child: Material(
            color: active
                ? colorScheme.surfaceContainerLow
                : Colors.transparent,
            borderRadius: _TabChip._borderRadius,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                if (!_secondaryArmed) {
                  widget.onTap();
                }
                _secondaryArmed = false;
              },
              onSecondaryTapUp: onContextMenu == null
                  ? null
                  : (details) => onContextMenu(tab, details.globalPosition),
              onLongPress: onContextMenu == null
                  ? null
                  : () {
                      final box = context.findRenderObject() as RenderBox?;
                      if (box != null) {
                        onContextMenu(tab, box.localToGlobal(Offset.zero));
                      }
                    },
              borderRadius: _TabChip._borderRadius,
              child: Container(
                constraints: const BoxConstraints(maxWidth: _TabChip.maxWidth),
                padding: const EdgeInsets.only(left: 10, right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isMarkdown
                          ? Icons.description_outlined
                          : Icons.text_snippet_outlined,
                      size: 15,
                      color: active
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: active
                              ? colorScheme.onSurface
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (tab.hasUnsavedChanges)
                      Padding(
                        padding: const EdgeInsets.only(left: 6, right: 2),
                        child: Icon(
                          Icons.circle,
                          size: 7,
                          color: colorScheme.primary,
                        ),
                      ),
                    ?widget.dragHandle,
                    _TabCloseButton(onPressed: widget.onClose),
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

/// 紧凑的圆形关闭按钮：24×24 命中区，13px 图标，
/// hover 时显示淡灰背景与「关闭」提示。
class _TabCloseButton extends StatelessWidget {
  const _TabCloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: '关闭',
      child: Tooltip(
        message: '关闭',
        excludeFromSemantics: true,
        waitDuration: const Duration(milliseconds: 500),
        child: SizedBox(
          width: 24,
          height: 24,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(5),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(5),
              child: const Center(child: Icon(Icons.close_rounded, size: 13)),
            ),
          ),
        ),
      ),
    );
  }
}

const _txtExtension = '.txt';

/// 标签展示名：与目录树 `_treeDisplayName` 一致地剥掉 `.txt` 后缀（大小写
/// 不敏感），其余文件名原样返回。
String _tabDisplayName(String name) {
  if (name.length > _txtExtension.length &&
      name.toLowerCase().endsWith(_txtExtension)) {
    return name.substring(0, name.length - _txtExtension.length);
  }
  return name;
}
