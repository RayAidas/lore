import 'package:flutter/material.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_ui/lore_ui.dart';
import 'package:path/path.dart' as p;

import 'library_failure_snackbar.dart';
import 'workspace_controller.dart';

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
