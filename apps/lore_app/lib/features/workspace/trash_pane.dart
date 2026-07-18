import 'package:flutter/material.dart';
import 'package:lore_application/lore_application.dart';

import 'library_failure_snackbar.dart';
import 'workspace_controller.dart';

/// 回收站页面：列出条目，支持恢复、永久删除与清空。
class TrashPage extends StatefulWidget {
  const TrashPage({required this.controller, super.key});

  final WorkspaceController controller;

  @override
  State<TrashPage> createState() => _TrashPageState();
}

final class _TrashPageState extends State<TrashPage> {
  Future<List<TrashItem>>? _future;

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

  /// controller 在删除/恢复后 notify，自动重新载入回收站列表。
  void _onControllerChanged() {
    if (mounted) {
      setState(_reload);
    }
  }

  void _reload() {
    _future = widget.controller.listTrashItems();
  }

  Future<void> _refresh() async {
    setState(_reload);
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
    return Scaffold(
      appBar: AppBar(title: const Text('回收站')),
      body: FutureBuilder<List<TrashItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }
          final items = snapshot.data ?? const <TrashItem>[];
          if (items.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete_outline, size: 40),
                  SizedBox(height: 12),
                  Text('回收站为空'),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                leading: Icon(_typeIcon(item.type)),
                title: Text(item.originalRelativePath),
                subtitle: Text(
                  '${_typeLabel(item.type)} · ${item.deletedAt.toLocal()}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => _restore(item),
                      child: const Text('恢复'),
                    ),
                    IconButton(
                      tooltip: '永久删除',
                      icon: const Icon(Icons.delete_forever_outlined),
                      onPressed: () => _purge(item),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _empty,
        icon: const Icon(Icons.delete_sweep_outlined),
        label: const Text('清空回收站'),
      ),
    );
  }

  Future<void> _restore(TrashItem item) async {
    try {
      await widget.controller.restoreTrashItem(item.token);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已恢复：${item.originalRelativePath}')),
        );
      }
      await _refresh();
    } on LibraryOperationException catch (error) {
      _showFailure(error.failure);
    }
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
      await _refresh();
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
      await _refresh();
    } on LibraryOperationException catch (error) {
      _showFailure(error.failure);
    }
  }

  Future<bool?> _confirm({required String title, required String message}) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
  }

  void _showFailure(LibraryFailure failure) {
    if (!mounted) {
      return;
    }
    showLibraryFailure(context, failure);
  }
}
