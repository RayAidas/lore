import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:path/path.dart' as p;

import 'inspector_empty.dart';
import 'name_prompt_dialog.dart';
import 'novel_overview_pane.dart';
import 'workspace_controller.dart';

/// 小说结构面板：卷/章列表，支持新建、重命名、移动、删除、重排。
final class NovelStructurePane extends StatelessWidget {
  const NovelStructurePane({
    required this.controller,
    required this.snapshot,
    required this.selectedEntry,
    required this.onFailure,
    super.key,
  });

  final WorkspaceController controller;
  final NovelSnapshot snapshot;
  final LibraryEntry selectedEntry;
  final ValueChanged<LibraryFailure> onFailure;

  ContentId get _parentId {
    if (selectedEntry.semanticKind == LibraryEntrySemanticKind.volume) {
      return ContentId(selectedEntry.semanticId!);
    }
    return snapshot.metadata.body.id;
  }

  @override
  Widget build(BuildContext context) {
    final nodes = snapshot.contentTree.childrenOf(_parentId);
    final isVolume =
        selectedEntry.semanticKind == LibraryEntrySemanticKind.volume;
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 28, 24, 18),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    isVolume
                        ? Icons.folder_copy_outlined
                        : Icons.menu_book_outlined,
                    size: 23,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isVolume ? selectedEntry.name : snapshot.metadata.title,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        isVolume
                            ? '${nodes.length} 章'
                            : '${snapshot.contentTree.nodes.where((node) => node.type == ContentNodeType.volume).length} 卷 · ${snapshot.contentTree.nodes.where((node) => node.type == ContentNodeType.chapter).length} 章',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '小说概览',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => Scaffold(
                        appBar: AppBar(title: const Text('小说概览')),
                        body: NovelOverviewPage(
                          controller: controller,
                          novelId: snapshot.metadata.id,
                        ),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.dashboard_outlined),
                ),
                if (!isVolume)
                  FilledButton.tonalIcon(
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => _run(
                      () => controller.createVolume(snapshot.metadata.id),
                    ),
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('新建卷'),
                  ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => _run(
                    () => controller.createChapter(
                      snapshot.metadata.id,
                      volumeId: isVolume ? _parentId : null,
                    ),
                  ),
                  icon: const Icon(Icons.note_add_outlined),
                  label: const Text('新建章'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (controller.reconciliationIssues.isNotEmpty)
            MaterialBanner(
              content: Text(controller.reconciliationIssues.first.message),
              actions: const [SizedBox.shrink()],
            ),
          Expanded(
            child: nodes.isEmpty
                ? Center(
                    child: InspectorEmpty(
                      icon: isVolume
                          ? Icons.article_outlined
                          : Icons.menu_book_outlined,
                      message: isVolume ? '本卷还没有章节' : '正文还没有卷或章节',
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
                    itemCount: nodes.length,
                    onReorderItem: (oldIndex, newIndex) {
                      _run(
                        () => controller.reorderContentNode(
                          snapshot.metadata.id,
                          nodes[oldIndex].id,
                          newIndex,
                        ),
                      );
                    },
                    itemBuilder: (context, index) {
                      final node = nodes[index];
                      return Padding(
                        key: ValueKey(node.id.value),
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: colorScheme.surfaceContainerLowest,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(color: colorScheme.outlineVariant),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            leading: Icon(
                              node.type == ContentNodeType.volume
                                  ? Icons.folder_copy_outlined
                                  : Icons.article_outlined,
                              color: node.type == ContentNodeType.volume
                                  ? colorScheme.secondary
                                  : colorScheme.primary,
                            ),
                            title: Text(p.basename(node.relativePath)),
                            subtitle: Text(
                              node.type == ContentNodeType.volume
                                  ? '${snapshot.contentTree.childrenOf(node.id).length} 章'
                                  : node.number == null
                                  ? '未编号章节'
                                  : '第 ${node.number} 章',
                            ),
                            onTap: () {
                              final entry = _entryForNode(node);
                              controller.selectEntry(entry);
                              if (node.type == ContentNodeType.chapter) {
                                unawaited(
                                  controller.openPath(entry.relativePath),
                                );
                              }
                            },
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (node.type == ContentNodeType.chapter)
                                  PopupMenuButton<String>(
                                    tooltip: '移动章节',
                                    constraints: const BoxConstraints(
                                      minWidth: 184,
                                      maxWidth: 280,
                                    ),
                                    onSelected: (target) => _run(
                                      () => controller.moveChapter(
                                        snapshot.metadata.id,
                                        node.id,
                                        volumeId: target == 'body'
                                            ? null
                                            : ContentId(target),
                                      ),
                                    ),
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: 'body',
                                        height: 34,
                                        child: Text('移动到正文根级'),
                                      ),
                                      ...snapshot.contentTree.nodes
                                          .where(
                                            (candidate) =>
                                                candidate.type ==
                                                ContentNodeType.volume,
                                          )
                                          .map(
                                            (volume) => PopupMenuItem(
                                              value: volume.id.value,
                                              height: 34,
                                              child: Text(
                                                '移动到 ${p.basename(volume.relativePath)}',
                                              ),
                                            ),
                                          ),
                                    ],
                                    icon: const Icon(
                                      Icons.drive_file_move_outline,
                                      size: 19,
                                    ),
                                  ),
                                IconButton(
                                  tooltip: '重命名',
                                  onPressed: () => _rename(context, node),
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                  ),
                                ),
                                IconButton(
                                  tooltip: '删除',
                                  onPressed: () => _deleteNode(context, node),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                  ),
                                ),
                                const Icon(Icons.drag_handle, size: 19),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  LibraryEntry _entryForNode(ContentNode node) {
    final relativePath = p.join(snapshot.rootPath, node.relativePath);
    return LibraryEntry(
      name: p.basename(node.relativePath),
      relativePath: relativePath,
      type: node.type == ContentNodeType.volume
          ? LibraryEntryType.directory
          : p.extension(node.relativePath).toLowerCase() == '.txt'
          ? LibraryEntryType.textFile
          : LibraryEntryType.markdownFile,
      semanticKind: node.type == ContentNodeType.volume
          ? LibraryEntrySemanticKind.volume
          : LibraryEntrySemanticKind.chapter,
      semanticId: node.id.value,
      novelId: snapshot.metadata.id.value,
      semanticOrder: node.order,
    );
  }

  Future<void> _rename(BuildContext context, ContentNode node) async {
    final extension = node.type == ContentNodeType.chapter
        ? p.extension(node.relativePath)
        : null;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => NamePromptDialog(
        title: node.type == ContentNodeType.volume ? '重命名卷' : '重命名章节',
        label: '新名称',
        initialValue: extension == null
            ? p.basename(node.relativePath)
            : p.basenameWithoutExtension(node.relativePath),
        suffix: extension,
      ),
    );
    if (name != null) {
      await _run(
        () => controller.renameContentNode(snapshot.metadata.id, node.id, name),
      );
    }
  }

  Future<void> _deleteNode(BuildContext context, ContentNode node) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除？'),
        content: Text('“${p.basename(node.relativePath)}”将移到回收站，可在回收站恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _run(
        () => controller.deleteContentNode(snapshot.metadata.id, node.id),
      );
    }
  }

  Future<void> _run(Future<Object?> Function() operation) async {
    try {
      await operation();
    } on LibraryOperationException catch (error) {
      onFailure(error.failure);
    }
  }
}
