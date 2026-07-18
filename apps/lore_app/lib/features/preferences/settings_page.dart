import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_ui/lore_ui.dart';

import 'preferences_providers.dart';

final class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsAsync = ref.watch(appPreferencesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: prefsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('无法加载设置：$error'),
          ),
        ),
        data: (prefs) => _SettingsBody(prefs: prefs),
      ),
    );
  }
}

class _SettingsBody extends ConsumerWidget {
  const _SettingsBody({required this.prefs});

  final AppPreferences prefs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(appPreferencesProvider.notifier);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _SectionHeader('外观'),
        ListTile(
          leading: const Icon(Icons.palette_outlined),
          title: const Text('主题'),
          trailing: DropdownButton<AppThemeMode>(
            value: prefs.themeMode,
            onChanged: (value) {
              if (value != null) controller.setThemeMode(value);
            },
            items: const [
              DropdownMenuItem(value: AppThemeMode.system, child: Text('跟随系统')),
              DropdownMenuItem(value: AppThemeMode.light, child: Text('极简白')),
              DropdownMenuItem(value: AppThemeMode.sepia, child: Text('纸张')),
              DropdownMenuItem(value: AppThemeMode.dark, child: Text('夜间')),
            ],
          ),
        ),
        const Divider(),
        _SectionHeader('编辑器'),
        ListTile(
          leading: const Icon(Icons.note_add_outlined),
          title: const Text('默认章节格式'),
          trailing: DropdownButton<ChapterFormat>(
            value: prefs.defaultChapterFormat,
            onChanged: (value) {
              if (value != null) controller.setDefaultChapterFormat(value);
            },
            items: const [
              DropdownMenuItem(
                value: ChapterFormat.markdown,
                child: Text('Markdown'),
              ),
              DropdownMenuItem(value: ChapterFormat.text, child: Text('TXT')),
            ],
          ),
        ),
        _SliderTile(
          icon: Icons.format_size_outlined,
          label: '字号',
          value: prefs.editorFontSize,
          min: 12,
          max: 28,
          divisions: 16,
          format: (value) => value.toStringAsFixed(0),
          onChanged: controller.setEditorFontSize,
        ),
        _SliderTile(
          icon: Icons.format_line_spacing,
          label: '行高',
          value: prefs.editorLineHeight,
          min: 1.2,
          max: 3,
          divisions: 18,
          format: (value) => value.toStringAsFixed(2),
          onChanged: controller.setEditorLineHeight,
        ),
        _SliderTile(
          icon: Icons.swap_horiz,
          label: '行宽',
          value: prefs.editorContentWidth,
          min: 560,
          max: 1200,
          divisions: 64,
          format: (value) => value.toStringAsFixed(0),
          onChanged: controller.setEditorContentWidth,
        ),
        const Divider(),
        _SectionHeader('写作目标'),
        ListTile(
          leading: const Icon(Icons.flag_outlined),
          title: const Text('每日字数目标'),
          subtitle: Text(
            prefs.dailyWordGoal == 0 ? '未设置' : '${prefs.dailyWordGoal} 字 / 天',
          ),
          trailing: IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _editDailyGoal(context, ref),
          ),
        ),
        const Divider(),
        _SectionHeader('查找替换'),
        SwitchListTile(
          secondary: const Icon(Icons.text_fields),
          title: const Text('区分大小写'),
          subtitle: const Text('新查找窗口的默认选项'),
          value: prefs.findMatchCase,
          onChanged: controller.setFindMatchCase,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.code),
          title: const Text('正则表达式'),
          subtitle: const Text('新查找窗口的默认选项'),
          value: prefs.findUseRegex,
          onChanged: controller.setFindUseRegex,
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> _editDailyGoal(BuildContext context, WidgetRef ref) async {
    final value = await showLoreTextPromptDialog(
      context: context,
      title: '每日字数目标',
      label: '字数',
      initialValue: prefs.dailyWordGoal == 0
          ? ''
          : prefs.dailyWordGoal.toString(),
      helperText: '留空或填 0 表示不设置目标',
      keyboardType: TextInputType.number,
      confirmLabel: '保存',
    );
    if (value == null) {
      return;
    }
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed < 0) {
      return;
    }
    await ref.read(appPreferencesProvider.notifier).setDailyWordGoal(parsed);
  }
}

final class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

final class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.format,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: Icon(icon),
          title: Text(label),
          trailing: Text(
            format(value),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
