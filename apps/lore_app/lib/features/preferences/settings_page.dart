import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_ui/lore_ui.dart';

import 'font_options.dart';
import 'preferences_providers.dart';

/// 以辅助面板形态打开设置（标题/副标题/图标/宽度集中在此，供工作区、侧栏、
/// 启动页复用）。
Future<void> showSettingsPanel(BuildContext context) {
  return showLorePanelSheet<void>(
    context: context,
    title: '设置',
    subtitle: '外观、编辑器与写作偏好',
    icon: Icons.settings_outlined,
    maxWidth: 760,
    child: const SettingsContent(),
  );
}

/// 设置面板内容（无 Scaffold 包装）：外观 / 编辑器 / 段落排版 / 沉浸写作 /
/// 写作目标 / 查找替换，按分组卡片呈现，宽屏两列、窄屏单列。加载失败可重试。
final class SettingsContent extends ConsumerWidget {
  const SettingsContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsAsync = ref.watch(appPreferencesProvider);
    return prefsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => _SettingsError(error: error),
      data: (prefs) => _SettingsBody(prefs: prefs),
    );
  }
}

final class _SettingsError extends ConsumerWidget {
  const _SettingsError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 36,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text('无法加载设置', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => ref.invalidate(appPreferencesProvider),
              child: const Text('重试'),
            ),
          ],
        ),
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
    // 设置 setter 返回 Future<void>；包成同步回调并捕获异步失败，避免 Future 被
    // 静默丢弃（磁盘写入失败时弹 toast，而非无反馈地停在旧值）。
    ValueChanged<T> guard<T>(Future<void> Function(T) fn) => (T value) {
      fn(value).catchError((Object _) {
        if (context.mounted) {
          LoreToast.error(context, '设置保存失败，请重试');
        }
      });
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cards = <Widget>[
            _SettingsCard(
              icon: Icons.palette_outlined,
              title: '外观',
              children: [
                _SettingRow(
                  label: '主题',
                  trailing: _Dropdown<AppThemeMode>(
                    value: prefs.themeMode,
                    onChanged: guard(controller.setThemeMode),
                    items: const [
                      _DropdownOption(AppThemeMode.system, '跟随系统'),
                      _DropdownOption(AppThemeMode.light, '极简白'),
                      _DropdownOption(AppThemeMode.sepia, '纸张'),
                      _DropdownOption(AppThemeMode.dark, '夜间'),
                    ],
                  ),
                ),
              ],
            ),
            _SettingsCard(
              icon: Icons.edit_outlined,
              title: '编辑器',
              children: [
                _SettingRow(
                  label: '默认章节格式',
                  trailing: _Dropdown<ChapterFormat>(
                    value: prefs.defaultChapterFormat,
                    onChanged: guard(controller.setDefaultChapterFormat),
                    items: const [
                      _DropdownOption(ChapterFormat.markdown, 'Markdown'),
                      _DropdownOption(ChapterFormat.text, 'TXT'),
                    ],
                  ),
                ),
                _SettingRow(
                  label: '字体',
                  trailing: _Dropdown<AppFontFamily>(
                    value: prefs.editorFontFamily,
                    onChanged: guard(controller.setEditorFontFamily),
                    items: [
                      for (final entry in AppFontOptions.options.entries)
                        _DropdownOption<AppFontFamily>(
                          entry.key,
                          entry.value.label,
                          // 选项用自身字体渲染，便于直观对比。
                          labelWidget: Text(
                            entry.value.label,
                            style: TextStyle(
                              fontFamily: entry.value.fontFamily,
                              fontFamilyFallback:
                                  entry.value.fontFamilyFallback,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                _SettingSlider(
                  label: '字号',
                  value: prefs.editorFontSize,
                  min: 12,
                  max: 28,
                  divisions: 16,
                  format: (v) => v.toStringAsFixed(0),
                  onChanged: guard(controller.setEditorFontSize),
                ),
                _SettingSlider(
                  label: '行高',
                  value: prefs.editorLineHeight,
                  min: 1.2,
                  max: 3,
                  divisions: 18,
                  format: (v) => v.toStringAsFixed(2),
                  onChanged: guard(controller.setEditorLineHeight),
                ),
                _SettingSlider(
                  label: '行宽',
                  value: prefs.editorContentWidth,
                  min: 560,
                  max: 1200,
                  divisions: 64,
                  format: (v) => v.toStringAsFixed(0),
                  onChanged: guard(controller.setEditorContentWidth),
                ),
              ],
            ),
            _SettingsCard(
              icon: Icons.format_align_left,
              title: '段落排版',
              children: [
                _SettingRow(
                  label: '首行缩进两字',
                  subtitle: '新段落段首空两个全角空格（仅 TXT）',
                  trailing: Switch(
                    value: prefs.firstLineIndent,
                    onChanged: guard(controller.setFirstLineIndent),
                  ),
                ),
                _SettingSlider(
                  label: '段间距',
                  value: prefs.paragraphSpacing,
                  min: 0,
                  max: 40,
                  divisions: 40,
                  format: (v) => v.toStringAsFixed(0),
                  onChanged: guard(controller.setParagraphSpacing),
                ),
                _SettingRow(
                  label: '网格线',
                  trailing: _Dropdown<GridLineMode>(
                    value: prefs.gridLineMode,
                    onChanged: guard(controller.setGridLineMode),
                    items: const [
                      _DropdownOption(GridLineMode.none, '无'),
                      _DropdownOption(GridLineMode.solid, '实线'),
                      _DropdownOption(GridLineMode.dashed, '虚线'),
                    ],
                  ),
                ),
                _SettingRow(
                  label: '高亮颜色',
                  subtitle: '选中文本右键高亮时的色板（点击色块修改）',
                  trailing: _HighlightPalette(
                    palette: prefs.highlightPalette,
                    onTapSlot: (i) => _editPaletteSlot(context, ref, i),
                  ),
                ),
              ],
            ),
            _SettingsCard(
              icon: Icons.center_focus_strong_outlined,
              title: '沉浸写作',
              children: [
                _SettingRow(
                  label: '打字机模式',
                  subtitle: '键入时保持光标行垂直居中（仅 TXT）',
                  trailing: Switch(
                    value: prefs.typewriterMode,
                    onChanged: guard(controller.setTypewriterMode),
                  ),
                ),
                _SettingRow(
                  label: '专注模式',
                  subtitle: '淡化非当前段落（仅 TXT）',
                  trailing: Switch(
                    value: prefs.focusMode,
                    onChanged: guard(controller.setFocusMode),
                  ),
                ),
              ],
            ),
            _SettingsCard(
              icon: Icons.flag_outlined,
              title: '写作目标',
              children: [
                _SettingRow(
                  label: '每日字数目标',
                  subtitle: prefs.dailyWordGoal == 0
                      ? '未设置'
                      : '${prefs.dailyWordGoal} 字 / 天',
                  trailing: IconButton(
                    tooltip: '修改',
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    onPressed: () => _editDailyGoal(context, ref),
                  ),
                ),
              ],
            ),
            _SettingsCard(
              icon: Icons.search_outlined,
              title: '查找替换',
              children: [
                _SettingRow(
                  label: '区分大小写',
                  subtitle: '新查找窗口的默认选项',
                  trailing: Switch(
                    value: prefs.findMatchCase,
                    onChanged: guard(controller.setFindMatchCase),
                  ),
                ),
                _SettingRow(
                  label: '正则表达式',
                  subtitle: '新查找窗口的默认选项',
                  trailing: Switch(
                    value: prefs.findUseRegex,
                    onChanged: guard(controller.setFindUseRegex),
                  ),
                ),
              ],
            ),
          ];

          // 宽屏两列配对：每个 Row 顶对齐，卡片各自高度，呈瀑布排列。
          if (constraints.maxWidth >= 600) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _cardRow(cards[0], cards[1]),
                const SizedBox(height: 12),
                _cardRow(cards[2], cards[3]),
                const SizedBox(height: 12),
                _cardRow(cards[4], cards[5]),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final card in cards) ...[card, const SizedBox(height: 12)],
            ],
          );
        },
      ),
    );
  }

  Widget _cardRow(Widget a, Widget b) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: a),
          const SizedBox(width: 12),
          Expanded(child: b),
        ],
      ),
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
    try {
      await ref.read(appPreferencesProvider.notifier).setDailyWordGoal(parsed);
    } catch (_) {
      if (context.mounted) {
        LoreToast.error(context, '设置保存失败，请重试');
      }
    }
  }

  Future<void> _editPaletteSlot(
    BuildContext context,
    WidgetRef ref,
    int slot,
  ) async {
    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择颜色'),
        content: SizedBox(
          width: 240,
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final c in _kHighlightPresetColors)
                GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(c),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(ctx).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected == null) {
      return;
    }
    final next = List<int>.from(prefs.highlightPalette);
    if (slot < next.length) {
      try {
        next[slot] = selected;
        await ref
            .read(appPreferencesProvider.notifier)
            .setHighlightPalette(next);
      } catch (_) {
        if (context.mounted) {
          LoreToast.error(context, '设置保存失败，请重试');
        }
      }
    }
  }
}

/// 调色板编辑用的扩展预设色（按色相分组，暖色在前契合 sepia）。
const List<int> _kHighlightPresetColors = <int>[
  // 红 / 粉
  0xFFFFCDD2, 0xFFEF9A9A, 0xFFEF5350, 0xFFEC407A, 0xFFF06292, 0xFFF48FB1,
  // 橙 / 黄
  0xFFFFCCBC, 0xFFFFAB91, 0xFFFF8A65, 0xFFFFD54F, 0xFFFFCA28, 0xFFFFEE58,
  // 绿 / 青
  0xFFDCE775, 0xFFAED581, 0xFFA5D6A7, 0xFF66BB6A, 0xFF26A69A, 0xFF80CBC4,
  // 蓝 / 紫
  0xFF81D4FA, 0xFF90CAF9, 0xFF42A5F5, 0xFF7986CB, 0xFF9575CD, 0xFFBA68C8,
  0xFFCE93D8,
  // 中性
  0xFFA1887F, 0xFF8D6E63, 0xFFB0BEC5, 0xFF78909C, 0xFF9E9D24,
];

/// 分组卡片：圆角 + 浅底 + 标题行（小图标 + 标题），内含若干设置行。
final class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 2),
            child: Row(
              children: [
                Icon(icon, size: 16, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

/// 标签 + 控件行：左侧标签（可带副标题），右侧任意控件（开关 / 下拉 / 按钮）。
final class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.label,
    required this.trailing,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: theme.textTheme.bodyMedium),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}

/// 标签 + 数值徽标 + 滑块行。
final class _SettingSlider extends StatelessWidget {
  const _SettingSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.format,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 8),
            child: Row(
              children: [
                Text(label, style: theme.textTheme.bodyMedium),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    format(value),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// 高亮色板：一排可点击的色块，点击触发 [onTapSlot] 编辑对应槽位。
final class _HighlightPalette extends StatelessWidget {
  const _HighlightPalette({required this.palette, required this.onTapSlot});

  final List<int> palette;
  final ValueChanged<int> onTapSlot;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outlineVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < palette.length; i++)
          Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
            child: GestureDetector(
              onTap: () => onTapSlot(i),
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: Color(palette[i]),
                  shape: BoxShape.circle,
                  border: Border.all(color: outline),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 下拉选项：[labelWidget] 可选，缺省时用 [label] 文本（字体预览用到自定义渲染）。
final class _DropdownOption<T> {
  const _DropdownOption(this.value, this.label, {this.labelWidget});

  final T value;
  final String label;
  final Widget? labelWidget;
}

/// 去下划线的下拉，视觉更克制。支持自定义选项渲染（字体预览）。
final class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final List<_DropdownOption<T>> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<T>(
      value: value,
      underline: const SizedBox(),
      isDense: true,
      style: Theme.of(context).textTheme.bodyMedium,
      onChanged: (next) {
        if (next != null) {
          onChanged(next);
        }
      },
      items: [
        for (final item in items)
          DropdownMenuItem<T>(
            value: item.value,
            child: item.labelWidget ?? Text(item.label),
          ),
      ],
    );
  }
}
