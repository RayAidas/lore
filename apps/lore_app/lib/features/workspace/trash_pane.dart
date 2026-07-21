import 'package:flutter/material.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_ui/lore_ui.dart';

import 'library_failure_snackbar.dart';
import 'workspace_controller.dart';

/// 以辅助面板形态打开回收站（标题/副标题/图标集中在此，供工作区与侧栏复用）。
Future<void> showTrashPanel(
  BuildContext context,
  WorkspaceController controller,
) {
  return showLorePanelSheet<void>(
    context: context,
    title: '回收站',
    subtitle: '恢复或彻底删除已移除的内容',
    icon: Icons.delete_outline,
    child: TrashPanel(controller: controller),
  );
}

/// 回收站面板内容（无 Scaffold 包装）：列出条目，支持恢复、永久删除与清空。
///
/// 供自适应辅助面板复用。[WorkspaceController] 在删除/恢复/清空后广播变化，
/// 本面板通过 listener 自动重新载入列表，无需在每次操作后手动 reload。
class TrashPanel extends StatefulWidget {
  const TrashPanel({required this.controller, super.key});

  final WorkspaceController controller;

  @override
  State<TrashPanel> createState() => _TrashPanelState();
}

final class _TrashPanelState extends State<TrashPanel> {
  List<TrashItem>? _items;
  Object? _error;
  bool _loading = true;
  // 重载序列号：丢弃过期结果，避免并发 reload 乱序覆盖（操作触发的 notify 与
  // 本面板自身的 reload 可能交错，晚完成的旧请求不应覆盖新请求）。
  int _reloadGen = 0;

  @override
  void initState() {
    super.initState();
    _reload();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  /// controller 在删除/恢复/清空后 notify，自动重新载入回收站列表。
  void _onControllerChanged() {
    if (mounted) {
      _reload();
    }
  }

  Future<void> _reload() async {
    final gen = ++_reloadGen;
    try {
      final items = await widget.controller.listTrashItems();
      if (!mounted || gen != _reloadGen) {
        return;
      }
      setState(() {
        _items = items;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || gen != _reloadGen) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  String _typeLabel(TrashItemType type) => switch (type) {
    TrashItemType.novel => '小说',
    TrashItemType.volume => '卷',
    TrashItemType.chapter => '章节',
    TrashItemType.entry => '文件',
  };

  IconData _typeIcon(TrashItemType type) => switch (type) {
    TrashItemType.novel => Icons.auto_stories_outlined,
    TrashItemType.volume => Icons.folder_copy_outlined,
    TrashItemType.chapter => Icons.article_outlined,
    TrashItemType.entry => Icons.insert_drive_file_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    Widget body;
    final hasItems = _items != null && _items!.isNotEmpty;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(child: Text('$_error'));
    } else if (!hasItems) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.delete_outline,
                  size: 30,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text('回收站为空', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                '删除的内容会先到这里，可随时恢复。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    } else {
      body = ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _items!.length,
        separatorBuilder: (_, _) => const SizedBox(height: 4),
        itemBuilder: (context, index) {
          final item = _items![index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _typeIcon(item.type),
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.originalRelativePath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                      Text(
                        '${_typeLabel(item.type)} · ${item.deletedAt.toLocal()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => _restore(item),
                  child: const Text('恢复'),
                ),
                IconButton(
                  tooltip: '永久删除',
                  icon: const Icon(Icons.delete_forever_outlined, size: 20),
                  onPressed: () => _purge(item),
                ),
              ],
            ),
          );
        },
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: body),
        if (hasItems) ...[
          Divider(height: 1, color: colorScheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Row(
              children: [
                Text(
                  '${_items!.length} 项',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: _empty,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: const Text('清空回收站'),
                  style: FilledButton.styleFrom(
                    foregroundColor: colorScheme.error,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _restore(TrashItem item) async {
    try {
      await widget.controller.restoreTrashItem(item.token);
      if (mounted) {
        LoreToast.success(context, '已恢复：${item.originalRelativePath}');
      }
    } on LibraryOperationException catch (error) {
      _showFailure(error.failure);
    }
    // 不手动 reload：controller 已 _notify()，会触发 _onControllerChanged → _reload。
  }

  Future<void> _purge(TrashItem item) async {
    final confirmed = await _confirm(
      title: '永久删除？',
      message: '“${item.originalRelativePath}”将被彻底删除，无法恢复。',
    );
    if (confirmed != true) {
      return;
    }
    try {
      await widget.controller.purgeTrashItem(item.token);
    } on LibraryOperationException catch (error) {
      _showFailure(error.failure);
    }
  }

  Future<void> _empty() async {
    final confirmed = await _confirm(
      title: '清空回收站？',
      message: '回收站中的所有内容将被彻底删除，无法恢复。',
    );
    if (confirmed != true) {
      return;
    }
    try {
      await widget.controller.emptyTrash();
    } on LibraryOperationException catch (error) {
      _showFailure(error.failure);
    }
  }

  Future<bool> _confirm({required String title, required String message}) {
    return showLoreConfirmDialog(
      context: context,
      title: title,
      message: message,
      confirmLabel: '永久删除',
      destructive: true,
    );
  }

  void _showFailure(LibraryFailure failure) {
    if (!mounted) {
      return;
    }
    showLibraryFailure(context, failure);
  }
}
