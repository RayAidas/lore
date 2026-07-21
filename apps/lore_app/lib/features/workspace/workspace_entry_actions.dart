import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_ui/lore_ui.dart';
import 'package:path/path.dart' as p;

import 'library_failure_snackbar.dart';
import 'workspace_controller.dart';
import 'workspace_platform.dart';

/// 重命名一个文档文件（章节或散文件）：弹输入框→选中目标路径（不动激活态）→
/// 按是否注册章节走结构服务或普通文件重命名。
///
/// 同时服务于目录树与标签栏的右键菜单，避免两处复制「章节 vs 散文件」分支与
/// 对话框/错误处理。注册章节走 [WorkspaceController.renameContentNode]（保持
/// content.json 同步），散文件走 [WorkspaceController.renameSelected]。重命名后
/// 标签路径由 [WorkspaceTabsStore.updatePathsAfterRename] 自动重映射。
Future<void> renameDocumentFlow({
  required BuildContext context,
  required WorkspaceController controller,
  required String relativePath,
  required String displayName,
}) async {
  // 初值取去扩展名主干，suffix 显示扩展名（目录树与标签栏一致）。
  final initial = p.basenameWithoutExtension(displayName);
  final suffix = p.extension(displayName);
  final name = await showLoreTextPromptDialog(
    context: context,
    title: '重命名',
    label: '新名称',
    initialValue: initial,
    suffixText: suffix,
  );
  if (name == null || !context.mounted) {
    return;
  }
  controller.selectPath(relativePath);
  try {
    final node = controller.chapterNodeForPath(relativePath);
    if (node != null) {
      await controller.renameContentNode(node.novelId, node.nodeId, name);
    } else {
      await controller.renameSelected(name);
    }
  } on LibraryOperationException catch (error) {
    if (!context.mounted) {
      return;
    }
    showLibraryFailure(context, error.failure);
  }
}

/// 把一个文档文件（章节或散文件）移到回收站：确认对话框→选中目标路径（不动
/// 激活态）→按是否注册章节走结构服务或普通删除。
///
/// 同时服务于目录树与标签栏的右键菜单。删除后标签由
/// [WorkspaceTabsStore.applyDeletionPathChanges] 自动关闭。
Future<void> deleteDocumentFlow({
  required BuildContext context,
  required WorkspaceController controller,
  required String relativePath,
  required String displayName,
}) async {
  final confirmed = await showLoreConfirmDialog(
    context: context,
    title: '删除？',
    message: '“$displayName”将移到回收站，可在回收站恢复。',
    confirmLabel: '删除',
    destructive: true,
  );
  if (!confirmed || !context.mounted) {
    return;
  }
  controller.selectPath(relativePath);
  try {
    final node = controller.chapterNodeForPath(relativePath);
    if (node != null) {
      await controller.deleteContentNode(node.novelId, node.nodeId);
    } else {
      await controller.deleteSelectedEntry();
    }
  } on LibraryOperationException catch (error) {
    if (!context.mounted) {
      return;
    }
    showLibraryFailure(context, error.failure);
  }
}

/// 右键/长按标签时弹出上下文菜单：标签管理（关闭类）+ 分屏 + 文件操作
/// （重命名/复制路径/Finder/移到回收站）。右键不激活标签——动作直接作用于
/// 被右键的 tab。
///
/// [onClose] 处理单个标签关闭（含冲突失败提示，由调用方决定 UI）；
/// [onSplitChanged] 在分屏结构变动（开/移/关分屏）后调用，供调用方清理状态
/// （如丢弃查找替换覆盖层）。
void showWorkspaceTabContextMenu({
  required BuildContext context,
  required WorkspaceController controller,
  required WorkspaceTab tab,
  required Offset position,
  required Future<void> Function(WorkspaceTab tab) onClose,
  required VoidCallback onSplitChanged,
}) {
  showLoreContextMenu(
    context: context,
    position: position,
    items: _buildTabContextMenuItems(
      context: context,
      controller: controller,
      tab: tab,
      onClose: onClose,
      onSplitChanged: onSplitChanged,
    ),
  );
}

List<LoreContextMenuItem> _buildTabContextMenuItems({
  required BuildContext context,
  required WorkspaceController controller,
  required WorkspaceTab tab,
  required Future<void> Function(WorkspaceTab tab) onClose,
  required VoidCallback onSplitChanged,
}) {
  final desktop = supportsDesktopSplit;
  final groupId = controller.groupForTab(tab);
  return <LoreContextMenuItem>[
    LoreContextMenuItem(label: '关闭', onTap: () => unawaited(onClose(tab))),
    LoreContextMenuItem(
      label: '关闭其他',
      onTap: () =>
          unawaited(_closeBatch(context, () => controller.closeOthers(tab))),
    ),
    LoreContextMenuItem(
      label: '关闭右侧',
      onTap: () => unawaited(
        _closeBatch(context, () => controller.closeTabsToRight(tab)),
      ),
    ),
    LoreContextMenuItem(
      label: '关闭全部',
      onTap: () => unawaited(
        _closeBatch(context, () => controller.closeAllTabsInGroup(tab)),
      ),
    ),
    if (desktop && !controller.isSplit)
      LoreContextMenuItem(
        label: '在右侧打开',
        onTap: () {
          onSplitChanged();
          controller.splitRight(tab);
        },
      ),
    if (desktop &&
        controller.isSplit &&
        groupId == WorkspaceEditorGroupId.primary)
      LoreContextMenuItem(
        label: '移到右侧',
        onTap: () {
          onSplitChanged();
          controller.moveTab(tab, WorkspaceEditorGroupId.secondary);
        },
      ),
    if (desktop &&
        controller.isSplit &&
        groupId == WorkspaceEditorGroupId.secondary)
      LoreContextMenuItem(
        label: '移到左侧',
        onTap: () {
          onSplitChanged();
          controller.moveTab(tab, WorkspaceEditorGroupId.primary);
        },
      ),
    if (desktop && controller.isSplit)
      LoreContextMenuItem(
        label: '关闭分屏',
        onTap: () {
          onSplitChanged();
          controller.closeSplit();
        },
      ),
    LoreContextMenuItem(
      label: '重命名',
      onTap: () => unawaited(
        renameDocumentFlow(
          context: context,
          controller: controller,
          relativePath: tab.relativePath,
          displayName: tab.name,
        ),
      ),
    ),
    LoreContextMenuItem(
      label: '复制路径',
      onTap: () => unawaited(_copyTabPath(context, tab)),
    ),
    if (controller.revealGateway != null)
      LoreContextMenuItem(
        label: '在 Finder 中显示',
        onTap: () => unawaited(controller.revealEntry(tab.relativePath)),
      ),
    LoreContextMenuItem(
      label: '移到回收站',
      destructive: true,
      onTap: () => unawaited(
        deleteDocumentFlow(
          context: context,
          controller: controller,
          relativePath: tab.relativePath,
          displayName: tab.name,
        ),
      ),
    ),
  ];
}

Future<void> _copyTabPath(BuildContext context, WorkspaceTab tab) async {
  await Clipboard.setData(ClipboardData(text: tab.relativePath));
  if (!context.mounted) {
    return;
  }
  LoreToast.success(context, '已复制路径');
}

/// 执行批量关闭；若存在因冲突无法关闭的标签，提示用户先处理。
Future<void> _closeBatch(
  BuildContext context,
  Future<List<WorkspaceTab>> Function() action,
) async {
  final stuck = await action();
  if (!context.mounted || stuck.isEmpty) {
    return;
  }
  LoreToast.warning(context, '${stuck.length} 个标签因冲突未关闭，请先处理');
}
