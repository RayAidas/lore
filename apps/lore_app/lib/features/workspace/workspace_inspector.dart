import 'package:flutter/material.dart';
import 'package:lore_domain/lore_domain.dart';

import 'inspector_empty.dart';
import 'open_document_extensions.dart';
import 'workspace_controller.dart';

/// 右侧工具栏：助手 / 大纲 / 信息 三栏。
final class WorkspaceInspector extends StatelessWidget {
  const WorkspaceInspector({required this.controller, super.key});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerLowest,
      child: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            const SizedBox(
              height: 60,
              child: TabBar(
                dividerHeight: 0,
                tabs: [
                  Tab(
                    height: 60,
                    icon: Icon(Icons.auto_awesome_outlined),
                    text: '助手',
                  ),
                  Tab(
                    height: 60,
                    icon: Icon(Icons.format_list_bulleted),
                    text: '大纲',
                  ),
                  Tab(height: 60, icon: Icon(Icons.info_outline), text: '信息'),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: TabBarView(
                children: [
                  const _AssistantPanel(),
                  _OutlinePanel(document: controller.activeDocument),
                  _DocumentInfoPanel(document: controller.activeDocument),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _AssistantPanel extends StatelessWidget {
  const _AssistantPanel();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colorScheme.primaryContainer.withValues(alpha: 0.7),
                colorScheme.tertiaryContainer.withValues(alpha: 0.45),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.auto_awesome, color: colorScheme.primary),
              const SizedBox(height: 14),
              Text(
                'AI 写作助手',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                '错别字检查、人物一致性与 Agent 对话将在后续版本启用。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text('计划能力', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        const _PlannedToolTile(
          icon: Icons.spellcheck_outlined,
          title: '校对与润色',
          subtitle: '检查错别字、病句和标点',
        ),
        const _PlannedToolTile(
          icon: Icons.groups_outlined,
          title: '设定一致性',
          subtitle: '结合书库资料检查人物与世界观',
        ),
        const _PlannedToolTile(
          icon: Icons.account_tree_outlined,
          title: 'Agent 工作流',
          subtitle: '读取并操作授权范围内的书库内容',
        ),
      ],
    );
  }
}

final class _PlannedToolTile extends StatelessWidget {
  const _PlannedToolTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 20),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.lock_clock_outlined, size: 16),
    );
  }
}

final class _OutlinePanel extends StatelessWidget {
  const _OutlinePanel({required this.document});

  final OpenDocument? document;

  @override
  Widget build(BuildContext context) {
    final current = document;
    if (current == null) {
      return const InspectorEmpty(
        icon: Icons.format_list_bulleted,
        message: '打开文档后查看大纲',
      );
    }
    if (!current.isMarkdown) {
      return const InspectorEmpty(
        icon: Icons.text_snippet_outlined,
        message: 'TXT 文档暂不生成大纲',
      );
    }
    return ListenableBuilder(
      listenable: current,
      builder: (context, _) => _buildOutline(context, current),
    );
  }

  Widget _buildOutline(BuildContext context, OpenDocument current) {
    final headings = <({int level, String title})>[];
    final headingPattern = RegExp(r'^(#{1,6})\s+(.+)$');
    for (final line in current.editorController.text.split('\n')) {
      final match = headingPattern.firstMatch(line.trimRight());
      if (match != null) {
        headings.add((level: match.group(1)!.length, title: match.group(2)!));
      }
    }
    if (headings.isEmpty) {
      return const InspectorEmpty(
        icon: Icons.tag_outlined,
        message: '使用 Markdown 标题生成文档大纲',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: headings.length,
      itemBuilder: (context, index) {
        final heading = headings[index];
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.only(
            left: 14.0 + (heading.level - 1) * 14,
            right: 14,
          ),
          leading: Icon(
            heading.level == 1 ? Icons.tag : Icons.subdirectory_arrow_right,
            size: 16,
          ),
          title: Text(
            heading.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }
}

final class _DocumentInfoPanel extends StatelessWidget {
  const _DocumentInfoPanel({required this.document});

  final OpenDocument? document;

  @override
  Widget build(BuildContext context) {
    final current = document;
    if (current == null) {
      return const InspectorEmpty(
        icon: Icons.info_outline,
        message: '打开文档后查看详细信息',
      );
    }
    return ListenableBuilder(
      listenable: current,
      builder: (context, _) => _buildInfo(context, current),
    );
  }

  Widget _buildInfo(BuildContext context, OpenDocument current) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(
          current.name,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          current.relativePath,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 22),
        _InfoRow(label: '格式', value: current.isMarkdown ? 'Markdown' : 'TXT'),
        _InfoRow(label: '字数', value: '${current.characterCount}'),
        _InfoRow(label: '状态', value: current.saveStatusText),
        _InfoRow(
          label: '换行符',
          value: current.snapshot.lineEnding.name.toUpperCase(),
        ),
        _InfoRow(
          label: '编码',
          value: current.snapshot.encoding == TextEncoding.utf8Bom
              ? 'UTF-8 BOM'
              : 'UTF-8',
        ),
      ],
    );
  }
}

final class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
