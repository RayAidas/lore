import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_ui/lore_ui.dart';

import 'font_options.dart';
import 'background_image_storage.dart';
import 'keybinding_recorder.dart';
import 'preferences_providers.dart';
import 'theme_options.dart';
import '../ai/ai_providers.dart';
import '../workspace/workspace_platform.dart';

part 'settings_controls.dart';
part 'ai_settings_controls.dart';

/// 以辅助面板形态打开设置（标题/副标题/图标/宽度集中在此，供工作区、侧栏、
/// 启动页复用）。[initialSection] 用 [_SettingsSection.keyName] 指定打开后定位到
/// 的分类（如 AI 写作助手未配置时「去设置」跳转）。
Future<void> showSettingsPanel(BuildContext context, {String? initialSection}) {
  return showLorePanelSheet<void>(
    context: context,
    title: '设置',
    icon: Icons.settings_outlined,
    maxWidth: 760,
    desktopMaxHeightFactor: 0.72,
    child: SettingsContent(initialSection: initialSection),
  );
}

/// 设置面板内容（无 Scaffold 包装）：桌面使用左侧分类导航，窄屏依次展示全部
/// 分组。加载失败时可重试。
final class SettingsContent extends ConsumerWidget {
  const SettingsContent({this.initialSection, super.key});

  /// 打开后定位到的分类 keyName（见 [_SettingsSection.keyName]）。
  final String? initialSection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsAsync = ref.watch(appPreferencesProvider);
    return prefsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => _SettingsError(error: error),
      data: (prefs) => _SettingsBody(prefs: prefs, initialSection: initialSection),
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

enum _SettingsSection {
  appearance(label: '外观', icon: Icons.palette_outlined, keyName: 'appearance'),
  layout(label: '排版', icon: Icons.format_align_left, keyName: 'layout'),
  writing(label: '写作偏好', icon: Icons.edit_note_outlined, keyName: 'writing'),
  ai(label: 'AI 写作助手', icon: Icons.auto_awesome_outlined, keyName: 'ai'),
  shortcuts(label: '快捷键', icon: Icons.keyboard_outlined, keyName: 'shortcuts');

  const _SettingsSection({
    required this.label,
    required this.icon,
    required this.keyName,
  });

  final String label;
  final IconData icon;
  final String keyName;
}

class _SettingsBody extends ConsumerStatefulWidget {
  const _SettingsBody({required this.prefs, this.initialSection});

  final AppPreferences prefs;

  /// 打开后定位到的分类 keyName（如 `ai`）；null 表示默认「外观」。
  final String? initialSection;

  @override
  ConsumerState<_SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends ConsumerState<_SettingsBody> {
  late _SettingsSection _selectedSection = _resolveInitialSection();
  final ScrollController _desktopScrollController = ScrollController();
  final GlobalKey _desktopScrollViewKey = GlobalKey();

  /// 把传入的 keyName 映射到分类；未知/缺失回落到「外观」。
  _SettingsSection _resolveInitialSection() {
    final keyName = widget.initialSection;
    if (keyName == null) {
      return _SettingsSection.appearance;
    }
    for (final section in _SettingsSection.values) {
      if (section.keyName == keyName) {
        return section;
      }
    }
    return _SettingsSection.appearance;
  }

  /// 桌面才显示「快捷键」分类——移动端无物理键盘，配了也触发不了。
  late final List<_SettingsSection> _visibleSections = supportsDesktopSplit
      ? _SettingsSection.values
      : [
          for (final section in _SettingsSection.values)
            if (section != _SettingsSection.shortcuts) section,
        ];
  late final Map<_SettingsSection, GlobalKey> _sectionKeys = {
    for (final section in _visibleSections) section: GlobalKey(),
  };
  _SettingsSection? _scrollTarget;
  // 滚动代际号：丢弃过期 _scrollToSection 的尾段。快速连点不同分类时，旧动画
  // 的 await 会先 resolve 并清空 _scrollTarget，使新动画中途失去闸门 → 高亮
  // 抖动；用代际号让旧请求作废，由最新一次 _scrollToSection 收尾。
  int _scrollGen = 0;

  AppPreferences get prefs => widget.prefs;

  Future<void> _chooseBackgroundImages() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    final sourcePaths = result?.files
        .map((file) => file.path)
        .whereType<String>()
        .toList();
    if (sourcePaths == null || sourcePaths.isEmpty || !mounted) {
      return;
    }
    final copiedPaths = <String>[];
    try {
      for (final sourcePath in sourcePaths) {
        copiedPaths.add(
          await BackgroundImageStorage.shared.importImage(sourcePath),
        );
      }
      if (!mounted) {
        await _deleteBackgroundImagesBestEffort(
          copiedPaths,
          operation: 'abandoned background images cleanup',
        );
        return;
      }
      await ref
          .read(appPreferencesProvider.notifier)
          .addBackgroundImages(copiedPaths);
    } catch (error, stackTrace) {
      await _deleteBackgroundImagesBestEffort(
        copiedPaths,
        operation: 'failed background images cleanup',
      );
      debugPrint('background image import failed: $error\n$stackTrace');
      if (mounted) {
        LoreToast.error(context, '无法导入背景图片，请重试');
      }
    }
  }

  Future<void> _removeBackgroundImage(String path) async {
    try {
      await ref
          .read(appPreferencesProvider.notifier)
          .removeBackgroundImage(path);
    } catch (error, stackTrace) {
      debugPrint('background image removal failed: $error\n$stackTrace');
      if (mounted) {
        LoreToast.error(context, '无法移除背景图片，请重试');
      }
      return;
    }
    await _deleteBackgroundImagesBestEffort([
      path,
    ], operation: 'removed background image cleanup');
  }

  Future<void> _deleteBackgroundImagesBestEffort(
    Iterable<String> paths, {
    required String operation,
  }) async {
    for (final path in paths) {
      try {
        await BackgroundImageStorage.shared.deleteManagedImage(path);
      } catch (error, stackTrace) {
        // 偏好提交成功后，副本清理失败不应把成功操作报告成失败。
        debugPrint('$operation failed: $error\n$stackTrace');
      }
    }
  }

  @override
  void initState() {
    super.initState();
    // 定位到指定分类（如 AI 助手未配置时「去设置」跳转）：首帧构建完成后滚动。
    if (widget.initialSection != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_scrollToSection(_selectedSection));
      });
    }
  }

  @override
  void dispose() {
    _desktopScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(appPreferencesProvider.notifier);
    // AI 写作助手的配置/Key 状态（单独 provider，异步加载）。
    final agentAsync = ref.watch(agentConfigProvider);
    // 设置 setter 返回 Future<void>；包成同步回调并捕获异步失败，避免 Future 被
    // 静默丢弃（磁盘写入失败时弹 toast，而非无反馈地停在旧值）。
    ValueChanged<T> guard<T>(Future<void> Function(T) fn) => (T value) {
      fn(value).catchError((Object error, StackTrace stack) {
        // 用户侧只弹 toast；这里保留诊断信息，避免磁盘写入失败被完全静默。
        debugPrint('settings save failed: $error\n$stack');
        if (context.mounted) {
          LoreToast.error(context, '设置保存失败，请重试');
        }
      });
    };
    // 快捷键的清除/重置等无参写操作同样需要失败兜底。
    void guardVoid(Future<void> Function() fn) {
      fn().catchError((Object error, StackTrace stack) {
        debugPrint('settings save failed: $error\n$stack');
        if (context.mounted) {
          LoreToast.error(context, '设置保存失败，请重试');
        }
      });
    }

    final sections = <_SettingsSection, List<Widget>>{
      _SettingsSection.appearance: [
        _SettingsGroup(
          title: '界面',
          children: [
            _ThemePicker(
              value: prefs.themeMode,
              onChanged: guard(controller.setThemeMode),
            ),
            _BackgroundGallery(
              paths: prefs.backgroundImagePaths,
              selectedPath: prefs.backgroundImagePath,
              onAdd: _chooseBackgroundImages,
              onSelect: (path) {
                // 点击未选中的图 → 设为背景；再点当前选中的图 → 取消，回到纯主题色。
                if (path == prefs.backgroundImagePath) {
                  guardVoid(controller.clearBackgroundImage);
                } else {
                  guard(controller.selectBackgroundImage)(path);
                }
              },
              onDelete: _removeBackgroundImage,
            ),
            if (prefs.backgroundImagePath != null) ...[
              _SettingSlider(
                label: '界面不透明度',
                value: prefs.backgroundOpacity,
                min: 0.15,
                max: 1,
                divisions: 17,
                format: (value) => '${(value * 100).round()}%',
                onChanged: guard(controller.setBackgroundOpacity),
              ),
              _SettingSlider(
                label: '图片遮罩',
                value: prefs.backgroundImageDimness,
                min: 0,
                max: 0.8,
                divisions: 16,
                format: (value) => '${(value * 100).round()}%',
                onChanged: guard(controller.setBackgroundImageDimness),
              ),
            ],
          ],
        ),
      ],
      _SettingsSection.layout: [
        _SettingsGroup(
          title: '编辑器显示',
          children: [
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
                      labelWidget: Text(
                        entry.value.label,
                        style: TextStyle(
                          fontFamily: entry.value.fontFamily,
                          fontFamilyFallback: entry.value.fontFamilyFallback,
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
              format: (value) => value.toStringAsFixed(0),
              onChanged: guard(controller.setEditorFontSize),
            ),
            _SettingSlider(
              label: '行高',
              value: prefs.editorLineHeight,
              min: 1.2,
              max: 3,
              divisions: 18,
              format: (value) => value.toStringAsFixed(2),
              onChanged: guard(controller.setEditorLineHeight),
            ),
            _SettingSlider(
              label: '正文宽度',
              value: prefs.editorContentWidth,
              min: 560,
              max: 1200,
              divisions: 64,
              format: (value) => value.toStringAsFixed(0),
              onChanged: guard(controller.setEditorContentWidth),
            ),
          ],
        ),
        _SettingsGroup(
          title: '段落',
          children: [
            _SettingRow(
              label: '首行缩进两字',
              subtitle: '新段落段首空两个全角空格（仅 TXT）',
              trailing: _CompactSwitch(
                value: prefs.firstLineIndent,
                onChanged: guard(controller.setFirstLineIndent),
              ),
            ),
            _SettingSlider(
              label: '段间距',
              value: prefs.paragraphSpacing,
              min: 0,
              max: 3,
              divisions: 60,
              format: (value) => value.toStringAsFixed(2),
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
              trailing: _HighlightPalette(
                palette: prefs.highlightPalette,
                onTapSlot: (index) => _editPaletteSlot(context, ref, index),
              ),
            ),
          ],
        ),
      ],
      _SettingsSection.writing: [
        _SettingsGroup(
          title: '沉浸写作',
          children: [
            _SettingRow(
              label: '打字机模式',
              subtitle: '键入时保持光标行垂直居中（仅 TXT）',
              trailing: _CompactSwitch(
                value: prefs.typewriterMode,
                onChanged: guard(controller.setTypewriterMode),
              ),
            ),
            _SettingRow(
              label: '专注模式',
              subtitle: '淡化非当前段落（仅 TXT）',
              trailing: _CompactSwitch(
                value: prefs.focusMode,
                onChanged: guard(controller.setFocusMode),
              ),
            ),
          ],
        ),
        _SettingsGroup(
          title: '写作目标',
          children: [
            _SettingRow(
              label: '每日字数目标',
              subtitle: prefs.dailyWordGoal == 0
                  ? '未设置'
                  : '${prefs.dailyWordGoal} 字 / 天',
              trailing: IconButton(
                tooltip: '修改',
                style: IconButton.styleFrom(
                  minimumSize: const Size.square(34),
                  maximumSize: const Size.square(34),
                  padding: EdgeInsets.zero,
                ),
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () => _editDailyGoal(context, ref),
              ),
            ),
          ],
        ),
        _SettingsGroup(
          title: '查找替换',
          children: [
            _SettingRow(
              label: '区分大小写',
              trailing: _CompactSwitch(
                value: prefs.findMatchCase,
                onChanged: guard(controller.setFindMatchCase),
              ),
            ),
            _SettingRow(
              label: '正则表达式',
              trailing: _CompactSwitch(
                value: prefs.findUseRegex,
                onChanged: guard(controller.setFindUseRegex),
              ),
            ),
          ],
        ),
      ],
      _SettingsSection.ai: [
        _SettingsGroup(
          title: 'AI 写作助手',
          children: [
            agentAsync.when(
              data: (state) => _AiSettingsContent(configState: state),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: Text('加载中…')),
              ),
              error: (error, stack) => _SettingRow(
                label: 'AI 配置加载失败',
                trailing: TextButton(
                  onPressed: () => ref.invalidate(agentConfigProvider),
                  child: const Text('重试'),
                ),
              ),
            ),
          ],
        ),
      ],
      _SettingsSection.shortcuts: [
        _SettingsGroup(
          title: '快捷键',
          children: [
            for (final action in ShortcutAction.values)
              _SettingRow(
                label: shortcutActionLabel(action),
                subtitle: shortcutActionDesktopOnly(action) ? '仅桌面' : null,
                trailing: KeybindingField(
                  key: ValueKey('keybinding-field-${action.name}'),
                  action: action,
                  combination: prefs.keybindings.bindings[action],
                  allBindings: prefs.keybindings.bindings,
                  onRecorded: (combo) =>
                      guardVoid(() => controller.setKeybinding(action, combo)),
                  onCleared: () =>
                      guardVoid(() => controller.clearKeybinding(action)),
                ),
              ),
            _SettingRow(
              label: '恢复默认',
              subtitle: '把所有快捷键重置为出厂设置',
              trailing: TextButton(
                onPressed: () => guardVoid(controller.resetKeybindings),
                child: const Text('全部恢复'),
              ),
            ),
          ],
        ),
      ],
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 600) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SettingsNavigation(
                selected: _selectedSection,
                sections: _visibleSections,
                onSelected: (section) => unawaited(_scrollToSection(section)),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: _handleDesktopScroll,
                  child: KeyedSubtree(
                    key: const ValueKey('settings-content-scroll'),
                    child: SingleChildScrollView(
                      key: _desktopScrollViewKey,
                      controller: _desktopScrollController,
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final section in _visibleSections) ...[
                            _SettingsSectionBlock(
                              key: _sectionKeys[section],
                              section: section,
                              children: sections[section]!,
                            ),
                            if (section != _visibleSections.last)
                              const _SettingsSectionDivider(),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            for (final section in _visibleSections) ...[
              _SettingsSectionHeader(section: section),
              ..._spacedSettingsGroups(sections[section]!),
              if (section != _visibleSections.last)
                const _SettingsSectionDivider(),
            ],
          ],
        );
      },
    );
  }

  Future<void> _scrollToSection(_SettingsSection section) async {
    final targetContext = _sectionKeys[section]?.currentContext;
    if (targetContext == null) {
      return;
    }
    final gen = ++_scrollGen;
    _scrollTarget = section;
    if (_selectedSection != section) {
      setState(() => _selectedSection = section);
    }
    await Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: 0,
    );
    // 期间若又触发了新的滚动（连点其他分类），本旧请求作废：不清闸门、不再
    // 同步，交由最新的那次 _scrollToSection 收尾，避免中途高亮抖动。
    if (!mounted || gen != _scrollGen) {
      return;
    }
    _scrollTarget = null;
    _syncSectionFromScroll();
  }

  bool _handleDesktopScroll(ScrollNotification notification) {
    if (_scrollTarget == null) {
      _syncSectionFromScroll();
    }
    return false;
  }

  void _syncSectionFromScroll() {
    if (!_desktopScrollController.hasClients) {
      return;
    }
    final position = _desktopScrollController.position;
    var next = _SettingsSection.appearance;
    if (position.extentAfter <= 2) {
      // 到底（容忍 2px 抖动）：末项可能永远到不了锚点行（内容短于视口时），
      // 用 extentAfter≈0 兜底，确保最后一个分类能被选中。
      next = _visibleSections.last;
    } else {
      final scrollBox = _desktopScrollViewKey.currentContext
          ?.findRenderObject();
      if (scrollBox is! RenderBox) {
        return;
      }
      // 锚点取滚动视口顶沿下方 48px：穿过该行的 section 即"当前"。
      // 48 ≈ section header 高度，让 header 完整露出后再计入切组。
      final anchorY = scrollBox.localToGlobal(Offset.zero).dy + 48;
      for (final section in _visibleSections) {
        final sectionBox = _sectionKeys[section]?.currentContext
            ?.findRenderObject();
        if (sectionBox is RenderBox &&
            sectionBox.localToGlobal(Offset.zero).dy <= anchorY) {
          next = section;
        }
      }
    }
    if (next != _selectedSection && mounted) {
      setState(() => _selectedSection = next);
    }
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
    if (!mounted) return;
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
    if (!mounted) return;
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

final class _SettingsNavigation extends StatelessWidget {
  const _SettingsNavigation({
    required this.selected,
    required this.sections,
    required this.onSelected,
  });

  final _SettingsSection selected;
  final List<_SettingsSection> sections;
  final ValueChanged<_SettingsSection> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('settings-navigation'),
      color: colorScheme.surfaceContainerLow,
      child: SizedBox(
        width: 176,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          children: [
            for (final section in sections)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Material(
                  color: selected == section
                      ? colorScheme.primaryContainer.withValues(alpha: 0.7)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  clipBehavior: Clip.antiAlias,
                  child: Semantics(
                    selected: selected == section,
                    button: true,
                    child: InkWell(
                      key: ValueKey('settings-nav-${section.keyName}'),
                      onTap: () => onSelected(section),
                      child: SizedBox(
                        height: 42,
                        child: Row(
                          children: [
                            if (selected == section)
                              SizedBox(
                                key: ValueKey(
                                  'settings-nav-selection-${section.keyName}',
                                ),
                              ),
                            const SizedBox(width: 12),
                            Icon(
                              section.icon,
                              size: 18,
                              color: selected == section
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              section.label,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    fontSize: 13.5,
                                    color: selected == section
                                        ? colorScheme.onPrimaryContainer
                                        : colorScheme.onSurfaceVariant,
                                    fontWeight: selected == section
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
          ],
        ),
      ),
    );
  }
}

/// 把多个设置组排成「组间留 16px、末组后不留白」的列表，供桌面 section block
/// 与窄屏列表两路复用，避免组间距逻辑在两处各自维护而漂移。
List<Widget> _spacedSettingsGroups(List<Widget> groups) {
  return [
    for (var index = 0; index < groups.length; index++) ...[
      groups[index],
      if (index < groups.length - 1) const SizedBox(height: 16),
    ],
  ];
}

final class _SettingsSectionBlock extends StatelessWidget {
  const _SettingsSectionBlock({
    required this.section,
    required this.children,
    super.key,
  });

  final _SettingsSection section;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: ValueKey('settings-section-${section.keyName}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingsSectionHeader(section: section),
        ..._spacedSettingsGroups(children),
      ],
    );
  }
}

/// 大类（外观 / 排版 / 写作偏好）之间的分隔线：比组内细分隔线留更多呼吸量，
/// 让三个 section 在视觉上清晰断开。
final class _SettingsSectionDivider extends StatelessWidget {
  const _SettingsSectionDivider();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Divider(
        height: 1,
        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
      ),
    );
  }
}

final class _SettingsSectionHeader extends StatelessWidget {
  const _SettingsSectionHeader({required this.section});

  final _SettingsSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(
        section.label,
        style: theme.textTheme.titleSmall?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.1,
        ),
      ),
    );
  }
}
