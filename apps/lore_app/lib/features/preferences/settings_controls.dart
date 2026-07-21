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

/// 一组带小标题的设置项，项间以细分隔线分隔。
final class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
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
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1)
              Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
              ),
          ],
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
