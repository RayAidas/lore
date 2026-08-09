part of 'settings_page.dart';

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

/// 一组带小标题的设置项。组内不再画分隔线（仅大类之间有），靠行高与组标题
/// 区隔；组与组之间的间距由外层 section 布局注入，末组后不加。
final class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 14,
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 4),
        ...children,
      ],
    );
  }
}

/// 应用背景图库。缩略图保持固定比例，选中态与删除动作直接叠加在图片上，避免
/// 为每张图片增加额外文字行而挤压设置面板。
final class _BackgroundGallery extends StatelessWidget {
  const _BackgroundGallery({
    required this.paths,
    required this.selectedPath,
    required this.onAdd,
    required this.onSelect,
    required this.onDelete,
  });

  final List<String> paths;
  final String? selectedPath;
  final VoidCallback onAdd;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('背景图片', style: theme.textTheme.bodyMedium),
              const Spacer(),
              Text(
                '${paths.length} 张',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final path in paths)
                _BackgroundThumbnail(
                  path: path,
                  selected: path == selectedPath,
                  onSelect: () => onSelect(path),
                  onDelete: () => onDelete(path),
                ),
              SizedBox(
                width: 116,
                height: 74,
                child: OutlinedButton(
                  key: const ValueKey('add-background-images'),
                  onPressed: onAdd,
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7),
                    ),
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined, size: 20),
                      SizedBox(height: 4),
                      Text('添加图片'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

final class _BackgroundThumbnail extends StatelessWidget {
  const _BackgroundThumbnail({
    required this.path,
    required this.selected,
    required this.onSelect,
    required this.onDelete,
  });

  final String path;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      key: ValueKey('background-thumbnail-$path'),
      selected: selected,
      button: true,
      label: selected ? '当前背景图片，再次点击取消' : '设为背景图片',
      child: SizedBox(
        width: 116,
        height: 74,
        child: Material(
          color: colorScheme.surfaceContainerLow,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(7),
            side: BorderSide(
              color: selected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: InkWell(
            onTap: onSelect,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  File(path),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (selected)
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Container(
                      width: 25,
                      height: 25,
                      margin: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.shadow.withValues(alpha: 0.2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: colorScheme.onPrimary,
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Tooltip(
                      message: '删除背景图片',
                      child: Material(
                        color: Colors.black.withValues(alpha: 0.58),
                        shape: const CircleBorder(),
                        child: InkWell(
                          onTap: onDelete,
                          customBorder: const CircleBorder(),
                          child: const SizedBox(
                            width: 25,
                            height: 25,
                            child: Icon(
                              Icons.close_rounded,
                              size: 15,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 主题选择器：以卡片网格展示所有主题（含「自动」跟随系统），点击即选。
///
/// 卡片预览直接取各主题真实 [ThemeData] 的 colorScheme 渲染迷你界面，所见即
/// 所选；与背景图库同为全宽块（不走 [_SettingRow]），让卡片有足够横向空间。
final class _ThemePicker extends StatelessWidget {
  const _ThemePicker({required this.value, required this.onChanged});

  final AppThemeMode value;
  final ValueChanged<AppThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('主题', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 12,
            children: [
              _ThemeCard.system(
                selected: value == AppThemeMode.system,
                onTap: () => onChanged(AppThemeMode.system),
              ),
              for (final option in AppThemeOptions.options)
                _ThemeCard(
                  option: option,
                  selected: value == option.mode,
                  onTap: () => onChanged(option.mode),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 单张主题卡片：上方迷你预览（取主题真实配色）+ 下方 2 字名；选中态用主色
/// 边框 + 角标勾选。「自动」卡走亮 / 暗分屏预览，区别于具名主题。
final class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.option,
    required this.selected,
    required this.onTap,
  }) : isSystem = false;

  const _ThemeCard.system({required this.selected, required this.onTap})
    : option = null,
      isSystem = true;

  static const double _previewWidth = 96;
  static const double _previewHeight = 60;

  final AppThemeOption? option;
  final bool isSystem;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = isSystem ? '自动' : option!.label;
    return Semantics(
      selected: selected,
      button: true,
      label: isSystem ? '跟随系统' : label,
      child: SizedBox(
        width: _previewWidth,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(9),
            child: Column(
              children: [
                SizedBox(
                  width: _previewWidth,
                  height: _previewHeight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected
                            ? colorScheme.primary
                            : colorScheme.outlineVariant,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    // 边框画在固定 SizedBox 内部：选中态由 1→2px 只向内吃，外框
                    // 尺寸不变，避免选中时卡片在网格里产生 1px 抖动。
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: isSystem
                          ? const _SystemThemePreview()
                          : _NamedThemePreview(option: option!),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.1,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? colorScheme.primary
                        : colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 具名主题的迷你预览：用主题 colorScheme 画一条假应用栏 + 几行正文 + 一个
/// 强调色角标，让用户一眼看到该主题的底色、文字与强调色搭配。
final class _NamedThemePreview extends StatelessWidget {
  const _NamedThemePreview({required this.option});

  final AppThemeOption option;

  @override
  Widget build(BuildContext context) {
    final cs = option.data.colorScheme;
    Widget line(double width, Color color) => Container(
      width: width,
      height: 3.5,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: ColoredBox(color: cs.surface)),
        // 假应用栏
        Positioned(
          left: 0,
          top: 0,
          right: 0,
          height: 13,
          child: ColoredBox(color: cs.surfaceContainerLowest),
        ),
        Positioned(
          left: 0,
          top: 13,
          right: 0,
          height: 1,
          child: ColoredBox(color: cs.outlineVariant),
        ),
        // 正文行
        Positioned(
          left: 8,
          top: 19,
          right: 8,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              line(54, cs.onSurface),
              const SizedBox(height: 4),
              line(72, cs.onSurfaceVariant),
              const SizedBox(height: 4),
              line(40, cs.onSurfaceVariant),
            ],
          ),
        ),
        // 强调色角标
        Positioned(
          right: 7,
          bottom: 7,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: cs.primary,
              shape: BoxShape.circle,
              border: Border.all(color: cs.surface, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

/// 「自动 / 跟随系统」的分屏预览：左半亮色、右半暗色，中央一个 auto 图标，
/// 表达「按系统亮度在两套方案间切换」。
final class _SystemThemePreview extends StatelessWidget {
  const _SystemThemePreview();

  @override
  Widget build(BuildContext context) {
    final host = Theme.of(context).colorScheme;
    final halfWidth = _ThemeCard._previewWidth / 2;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: halfWidth,
          child: ColoredBox(color: LoreTheme.light().colorScheme.surface),
        ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: halfWidth,
          child: ColoredBox(color: LoreTheme.dark().colorScheme.surface),
        ),
        Center(
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: host.surfaceContainerLowest,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: host.shadow.withValues(alpha: 0.25),
                  blurRadius: 3,
                ),
              ],
            ),
            child: Icon(
              Icons.brightness_auto_rounded,
              size: 13,
              color: host.onSurfaceVariant,
            ),
          ),
        ),
      ],
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
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13.5),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11.5,
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.3,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            trailing,
          ],
        ),
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
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: SizedBox(
        height: 46,
        child: Row(
          children: [
            SizedBox(
              width: 92,
              child: Text(label, style: theme.textTheme.bodyMedium),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14,
                  ),
                ),
                child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  divisions: divisions,
                  onChanged: onChanged,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 52,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(7),
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
    );
  }
}

/// 紧凑自绘开关：比 Material [Switch] 更小、配色与设置密度一致。
final class _CompactSwitch extends StatelessWidget {
  const _CompactSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      toggled: value,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onChanged(!value),
          borderRadius: BorderRadius.circular(11),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            width: 40,
            height: 22,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: value
                  ? colorScheme.primary
                  : colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: value ? colorScheme.primary : colorScheme.outlineVariant,
              ),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: value
                      ? colorScheme.onPrimary
                      : colorScheme.onSurfaceVariant,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.shadow.withValues(alpha: 0.16),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
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

/// 使用轻量弹出菜单的紧凑选择器。支持自定义选项渲染（字体预览）。
final class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    super.key,
  });

  final T value;
  final List<_DropdownOption<T>> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // value 一般都在 items 中；若 domain 新增枚举值未同步到 items，回退到首项
    // 而非抛 StateError，避免构造期崩溃（仍是配置 bug，但降级为显示首项）。
    var selected = items.first;
    for (final item in items) {
      if (item.value == value) {
        selected = item;
        break;
      }
    }
    return PopupMenuButton<T>(
      tooltip: '当前：${selected.label}',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 4),
      constraints: const BoxConstraints(minWidth: 132, maxWidth: 240),
      color: colorScheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final item in items)
          PopupMenuItem<T>(
            value: item.value,
            height: 38,
            child: Row(
              children: [
                Expanded(child: item.labelWidget ?? Text(item.label)),
                if (item.value == value)
                  Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: colorScheme.primary,
                  ),
              ],
            ),
          ),
      ],
      child: Container(
        height: 34,
        constraints: const BoxConstraints(minWidth: 112),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: DefaultTextStyle.merge(
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                child: selected.labelWidget ?? Text(selected.label),
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 17,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
