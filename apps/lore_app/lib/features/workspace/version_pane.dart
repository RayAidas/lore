import 'package:flutter/material.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_ui/lore_ui.dart';

import 'inspector_empty.dart';
import 'library_failure_snackbar.dart';
import 'workspace_controller.dart';

/// 右侧「版本」面板：列出当前活动文档的历史快照。点列表项 → 中间编辑器区
/// 切换为该版本与当前的 diff（[WorkspaceController.showHistoryDiff]）；当前
/// 对比的版本高亮。支持创建命名版本、恢复、删除。
class VersionPane extends StatefulWidget {
  const VersionPane({required this.controller, super.key});

  final WorkspaceController controller;

  @override
  State<VersionPane> createState() => _VersionPaneState();
}

final class _VersionPaneState extends State<VersionPane> {
  DocumentIdentity? _identity;
  List<HistorySnapshot> _snapshots = const [];
  bool _loading = true;
  Object? _error;
  String? _lastDocKey;
  int _reloadGen = 0;

  WorkspaceController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onChanged);
    _setupAndReload();
  }

  @override
  void dispose() {
    controller.removeListener(_onChanged);
    super.dispose();
  }

  /// controller notify 时：活动文档切换则重载列表，否则仅重绘（diffTarget 变化
  /// 引起的高亮切换）。
  void _onChanged() {
    if (!mounted) return;
    final key = controller.activeDocument?.relativePath;
    if (key != _lastDocKey) {
      _setupAndReload();
    } else {
      setState(() {});
    }
  }

  Future<void> _setupAndReload() async {
    final doc = controller.activeDocument;
    final newIdentity = doc == null ? null : controller.historyIdentityFor(doc);
    if (newIdentity?.logicalKey != _identity?.logicalKey) {
      _snapshots = const [];
      _loading = true;
    }
    _lastDocKey = doc?.relativePath;
    _identity = newIdentity;
    if (newIdentity == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    await _reload();
  }

  Future<void> _reload() async {
    final identity = _identity;
    if (identity == null) return;
    final gen = ++_reloadGen;
    try {
      final snapshots = await controller.listHistorySnapshots(identity);
      if (!mounted || gen != _reloadGen) return;
      setState(() {
        _snapshots = snapshots
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || gen != _reloadGen) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _createVersion() async {
    final identity = _identity;
    final doc = controller.activeDocument;
    if (identity == null || doc == null) return;
    final result = await _showCreateDialog();
    if (result == null) return;
    try {
      await controller.createHistoryVersion(
        identity,
        doc.snapshot.text,
        label: result.label.isEmpty ? null : result.label,
        note: result.note.isEmpty ? null : result.note,
      );
      if (!mounted) return;
      LoreToast.success(context, '已创建版本');
      await _reload();
    } on LibraryOperationException catch (error) {
      if (mounted) showLibraryFailure(context, error.failure);
    }
  }

  Future<({String label, String note})?> _showCreateDialog() {
    final labelCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    return showDialog<({String label, String note})>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('创建版本'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '名称',
                hintText: '如：交稿前',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '备注',
                hintText: '可选',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, (
              label: labelCtrl.text.trim(),
              note: noteCtrl.text.trim(),
            )),
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  Future<void> _restore(HistorySnapshot snap) async {
    final identity = _identity;
    if (identity == null) return;
    final confirmed = await showLoreConfirmDialog(
      context: context,
      title: '恢复此版本？',
      message: '当前内容会先自动留底，再用所选版本覆盖。',
      confirmLabel: '恢复',
    );
    if (confirmed != true) return;
    try {
      final result = await controller.restoreHistorySnapshot(identity, snap.id);
      if (!mounted) return;
      switch (result) {
        case RestoreSuccess():
          LoreToast.success(context, '已恢复到所选版本');
          await _reload();
        case RestoreConflict():
          showLibraryFailure(
            context,
            const LibraryFailure(
              code: LibraryFailureCode.externalModification,
              message: '磁盘已被外部修改，请先处理冲突再恢复。',
            ),
          );
      }
    } on LibraryOperationException catch (error) {
      if (mounted) showLibraryFailure(context, error.failure);
    }
  }

  Future<void> _delete(HistorySnapshot snap) async {
    final identity = _identity;
    if (identity == null) return;
    final confirmed = await showLoreConfirmDialog(
      context: context,
      title: '删除此快照？',
      message: '该历史快照将被永久删除，无法恢复。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (confirmed != true) return;
    try {
      await controller.deleteHistorySnapshot(identity, snap.id);
      if (mounted) await _reload();
    } on LibraryOperationException catch (error) {
      if (mounted) showLibraryFailure(context, error.failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final doc = controller.activeDocument;
    if (doc == null || _identity == null) {
      return const InspectorEmpty(
        icon: Icons.history_rounded,
        message: '打开文档后查看历史版本',
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            '无法加载历史版本',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    final diffId = controller.diffTarget?.snapshotId;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      doc.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${_snapshots.length} 个版本',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '创建版本',
                onPressed: _createVersion,
                icon: const Icon(Icons.bookmark_add_outlined, size: 20),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant),
        if (_snapshots.isEmpty)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  '还没有历史版本\n编辑后保存或切换章节即自动生成',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _snapshots.length,
              itemBuilder: (context, index) {
                final snap = _snapshots[index];
                return _versionTile(snap, snap.id == diffId, theme, cs);
              },
            ),
          ),
      ],
    );
  }

  Widget _versionTile(
    HistorySnapshot snap,
    bool selected,
    ThemeData theme,
    ColorScheme cs,
  ) {
    return InkWell(
      onTap: () {
        final doc = controller.activeDocument;
        if (doc != null) controller.showHistoryDiff(doc, snap);
      },
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              width: 3,
              color: selected ? cs.primary : Colors.transparent,
            ),
          ),
          color: selected ? cs.primaryContainer.withValues(alpha: 0.32) : null,
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                _triggerIcon(snap.trigger),
                size: 16,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTime(snap.createdAt),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  Text(
                    _triggerSubtitle(snap),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  if (snap.label != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      snap.label!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: '恢复',
              onPressed: () => _restore(snap),
              icon: const Icon(Icons.restore_rounded, size: 16),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              tooltip: '删除',
              onPressed: () => _delete(snap),
              icon: const Icon(Icons.delete_outline_rounded, size: 16),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  IconData _triggerIcon(HistoryTrigger trigger) => switch (trigger) {
    HistoryTrigger.autoCheckpoint => Icons.save_outlined,
    HistoryTrigger.autoThreshold => Icons.timeline_outlined,
    HistoryTrigger.manual => Icons.bookmark_outlined,
    HistoryTrigger.restoreSafeguard => Icons.history_toggle_off_outlined,
  };

  String _triggerSubtitle(HistorySnapshot snap) {
    final trigger = switch (snap.trigger) {
      HistoryTrigger.autoCheckpoint => '自动 · 保存',
      HistoryTrigger.autoThreshold => '自动 · 变更',
      HistoryTrigger.manual => '手动版本',
      HistoryTrigger.restoreSafeguard => '恢复留底',
    };
    return '$trigger  ·  ${snap.characterCount} 字';
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
