import 'package:flutter/material.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_editor/lore_editor.dart';

import 'document_pane.dart';
import 'document_tabs.dart';
import 'empty_workspace.dart';
import 'novel_structure_pane.dart';
import 'workspace_controller.dart';
import 'workspace_platform.dart';

/// [WorkspaceEditorGroup] 向 [LibraryWorkspacePage] 回调的集合。聚合成一个值类，
/// 避免组件构造参数爆炸（10+ 回调）。回调在页面 State 上是稳定的，可作为
/// `late final` 字段一次性构造。
final class WorkspaceEditorGroupCallbacks {
  const WorkspaceEditorGroupCallbacks({
    required this.onFocusGroup,
    required this.onExpandSidebar,
    required this.onActivateTab,
    required this.onDiscardFindReplace,
    required this.onDragStarted,
    required this.onDragEnded,
    required this.onCloseTab,
    required this.onContextMenu,
    required this.onStructureFailure,
    required this.onReloadConflict,
    required this.onToggleFullscreen,
    required this.onCloseFindReplace,
  });

  /// 点击该分组区域时聚焦它（更新 focusedGroupId）。
  final void Function(WorkspaceEditorGroupId groupId) onFocusGroup;

  /// 点击「展开侧栏」按钮（仅 [showSidebarExpander] 时渲染）。
  final VoidCallback onExpandSidebar;

  /// 激活（切到）某个标签。
  final Future<void> Function(WorkspaceTab tab) onActivateTab;

  /// 标签移动/分屏变动后丢弃查找替换覆盖层。
  final VoidCallback onDiscardFindReplace;

  final void Function(WorkspaceTabDragData data) onDragStarted;
  final VoidCallback onDragEnded;

  /// 关闭单个标签（含冲突失败提示，由页面处理）。
  final Future<void> Function(WorkspaceTab tab) onCloseTab;

  /// 右键/长按标签弹上下文菜单（页面转发到 [showWorkspaceTabContextMenu]）。
  final void Function(WorkspaceTab tab, Offset position) onContextMenu;

  /// 结构面板加载失败时提示。
  final void Function(LibraryFailure failure) onStructureFailure;

  /// 文档冲突时重新加载磁盘版本。
  final void Function(OpenDocument document) onReloadConflict;

  /// 切换页面级全屏（全屏态下文档工具条的「退出全屏」入口）。
  final VoidCallback onToggleFullscreen;

  /// 关闭查找替换覆盖层。
  final VoidCallback onCloseFindReplace;
}

/// 工作区单个编辑分组的呈现：标签行 +（结构面板 | 文档 | 空态）+ 查找替换覆盖层，
/// 分屏下外裹 [DragTarget] 接收跨组拖拽。从 [LibraryWorkspacePage] 抽出以控制
/// 主文件行数；行为与原 `_buildEditorGroup` 完全一致。
///
/// 全屏（[hideTabs] 为真）时标签行/分隔线折叠为零高度占位而非移除，保持其后
/// DocumentPane 在 Column 中的下标不变 → 切换全屏不重挂载编辑器。
final class WorkspaceEditorGroup extends StatelessWidget {
  const WorkspaceEditorGroup({
    required this.controller,
    required this.groupId,
    required this.session,
    required this.showSidebarExpander,
    required this.hideTabs,
    required this.findController,
    required this.findReplaceMode,
    required this.callbacks,
    super.key,
  });

  final WorkspaceController controller;
  final WorkspaceEditorGroupId groupId;
  final LibrarySession session;
  final bool showSidebarExpander;
  final bool hideTabs;
  final FindReplaceController? findController;
  final bool findReplaceMode;
  final WorkspaceEditorGroupCallbacks callbacks;

  @override
  Widget build(BuildContext context) {
    final selectedEntry = controller.selectedEntry;
    final selectedNovel = controller.selectedNovel;
    final showStructure =
        !hideTabs &&
        groupId == controller.focusedGroupId &&
        selectedNovel != null &&
        switch (selectedEntry?.semanticKind) {
          LibraryEntrySemanticKind.novel ||
          LibraryEntrySemanticKind.body ||
          LibraryEntrySemanticKind.volume => true,
          _ => false,
        };
    final activeDocument = controller.activeDocumentForGroup(groupId);
    final focused = controller.focusedGroupId == groupId;
    final editorGroup = Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => callbacks.onFocusGroup(groupId),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: focused && controller.isSplit
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary.withAlpha(80),
                )
              : null,
        ),
        child: Column(
          children: [
            // 折叠标签行（非移除）保 DocumentPane 下标不变，避免重挂载。
            if (hideTabs)
              const SizedBox.shrink()
            else
              Row(
                children: [
                  if (showSidebarExpander)
                    ColoredBox(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerLowest,
                      child: SizedBox(
                        width: 44,
                        height: DocumentTabs.barHeight,
                        child: IconButton(
                          key: const ValueKey('library-sidebar-expand'),
                          tooltip: '展开侧栏',
                          onPressed: callbacks.onExpandSidebar,
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.chevron_right_rounded),
                        ),
                      ),
                    ),
                  Expanded(
                    child: DocumentTabs(
                      controller: controller,
                      groupId: groupId,
                      onActivate: callbacks.onActivateTab,
                      onMove: callbacks.onDiscardFindReplace,
                      onDragStarted: callbacks.onDragStarted,
                      onDragEnded: callbacks.onDragEnded,
                      onClose: callbacks.onCloseTab,
                      onContextMenu: callbacks.onContextMenu,
                    ),
                  ),
                ],
              ),
            if (hideTabs) const SizedBox.shrink() else const Divider(height: 1),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: showStructure
                        ? NovelStructurePane(
                            controller: controller,
                            snapshot: selectedNovel,
                            selectedEntry: selectedEntry!,
                            onFailure: callbacks.onStructureFailure,
                          )
                        : activeDocument != null
                        ? DocumentPane(
                            controller: controller,
                            document: activeDocument,
                            session: session,
                            onReloadConflict: () =>
                                callbacks.onReloadConflict(activeDocument),
                            // hideTabs 仅在全屏为真：文档工具条显示「退出全屏」入口。
                            onToggleFullscreen: hideTabs
                                ? callbacks.onToggleFullscreen
                                : null,
                          )
                        : ColoredBox(
                            color: Theme.of(context).colorScheme.surface,
                            child: Center(
                              child: EmptyWorkspace(
                                hasSelection: controller.selectedPath != null,
                                selectedPath: controller.selectedPath,
                              ),
                            ),
                          ),
                  ),
                  if (findController != null &&
                      activeDocument != null &&
                      groupId == controller.focusedGroupId)
                    Positioned(
                      top: 56,
                      right: 12,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: SizedBox(
                          width: 440,
                          child: FindReplaceOverlay(
                            findController: findController!,
                            editorController: activeDocument.editorController,
                            initialShowReplace: findReplaceMode,
                            onClose: callbacks.onCloseFindReplace,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (!supportsDesktopSplit || !controller.isSplit) {
      return editorGroup;
    }
    return DragTarget<WorkspaceTabDragData>(
      onWillAcceptWithDetails: (details) =>
          details.data.sourceGroupId != groupId,
      onAcceptWithDetails: (details) {
        callbacks.onDiscardFindReplace();
        controller.moveTab(details.data.tab, groupId);
        callbacks.onDragEnded();
      },
      builder: (context, candidates, _) => DecoratedBox(
        decoration: BoxDecoration(
          color: candidates.isNotEmpty
              ? Theme.of(context).colorScheme.primaryContainer.withAlpha(55)
              : null,
          border: candidates.isNotEmpty
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                )
              : null,
        ),
        child: editorGroup,
      ),
    );
  }
}
