import 'package:flutter/material.dart';

import 'novel_search_controller.dart';
import 'novel_search_panel.dart';
import 'phone_preview/phone_preview_pane.dart';
import 'version_pane.dart';
import 'writing_statistics_pane.dart';
import 'workspace_controller.dart';

/// 竖向工具轨道的固定宽度（轨道 SizedBox 与每个标签单元共用）。公开供布局
/// 与测试共享同一处常量，避免魔法数漂移。
const double workspaceInspectorRailWidth = 50;

enum WorkspaceInspectorTab {
  assistant(
    label: '助手',
    icon: Icons.auto_awesome_outlined,
    keyName: 'assistant',
  ),
  statistics(
    label: '统计',
    icon: Icons.bar_chart_outlined,
    keyName: 'statistics',
  ),
  version(label: '版本', icon: Icons.history_rounded, keyName: 'version'),
  search(label: '搜索', icon: Icons.search_outlined, keyName: 'search'),
  preview(label: '预览', icon: Icons.smartphone_outlined, keyName: 'preview');

  const WorkspaceInspectorTab({
    required this.label,
    required this.icon,
    required this.keyName,
  });

  final String label;
  final IconData icon;
  final String keyName;
}

/// 右侧工具内容区，由最右侧的 [WorkspaceInspectorRail] 控制当前内容。
final class WorkspaceInspector extends StatelessWidget {
  const WorkspaceInspector({
    required this.controller,
    required this.tab,
    this.onSelectSearchMatch,
    super.key,
  });

  final WorkspaceController controller;
  final WorkspaceInspectorTab tab;

  /// 「搜索」tab 点匹配时回调到页面层做跳转桥接（打开章节 + 定位 + 整文高亮）。
  final void Function(ChapterSearchResult result, ChapterMatch match)?
  onSelectSearchMatch;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerLowest,
      child: switch (tab) {
        WorkspaceInspectorTab.assistant => const _AssistantPanel(),
        WorkspaceInspectorTab.statistics => WritingStatisticsPane(
          controller: controller,
        ),
        WorkspaceInspectorTab.version => VersionPane(controller: controller),
        WorkspaceInspectorTab.search => NovelSearchPanel(
          controller: controller,
          onSelectMatch: onSelectSearchMatch ?? (_, _) {},
        ),
        WorkspaceInspectorTab.preview => PhonePreviewPane(
          controller: controller,
        ),
      },
    );
  }
}

/// 始终停靠在工作区最右侧的竖向工具标签。
final class WorkspaceInspectorRail extends StatelessWidget {
  const WorkspaceInspectorRail({
    required this.selectedTab,
    required this.onSelected,
    super.key,
  });

  final WorkspaceInspectorTab? selectedTab;
  final ValueChanged<WorkspaceInspectorTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerLow,
      child: SizedBox(
        key: const ValueKey('workspace-inspector-rail'),
        width: workspaceInspectorRailWidth,
        child: Column(
          children: [
            const SizedBox(height: 6),
            for (final tab in WorkspaceInspectorTab.values)
              _InspectorRailTab(
                tab: tab,
                selected: selectedTab == tab,
                onPressed: () => onSelected(tab),
              ),
          ],
        ),
      ),
    );
  }
}

final class _InspectorRailTab extends StatelessWidget {
  const _InspectorRailTab({
    required this.tab,
    required this.selected,
    required this.onPressed,
  });

  final WorkspaceInspectorTab tab;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tab.label,
      child: Semantics(
        selected: selected,
        button: true,
        label: tab.label,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Material(
            color: selected
                ? colorScheme.primaryContainer.withValues(alpha: 0.68)
                : Colors.transparent,
            child: InkWell(
              key: ValueKey('workspace-inspector-tab-${tab.keyName}'),
              onTap: onPressed,
              child: Container(
                width: workspaceInspectorRailWidth,
                height: 52,
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: selected
                          ? colorScheme.primary
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      tab.icon,
                      size: 18,
                      color: selected
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tab.label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: selected
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                        fontSize: 10.5,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
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
