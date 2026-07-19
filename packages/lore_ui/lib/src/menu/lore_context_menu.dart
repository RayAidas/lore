import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'lore_menu_metrics.dart';

/// 上下文菜单项的展示描述：标签 + 触发回调 + 危险/禁用标志。
///
/// 不携带任何业务类型——调用方在自己的闭包里捕获目标对象（如目录条目、
/// 文档标签）。[onTap] 在菜单已关闭之后才被回调，因此可以在其中安全地
/// 弹出对话框或执行异步操作。
final class LoreContextMenuItem {
  const LoreContextMenuItem({
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool destructive;
  final bool enabled;
}

/// 在 [position]（全局坐标）处弹出一个上下文菜单。
///
/// 基于 [ContextMenuController]（底层 [TapRegion]，不消费指针）实现，而非
/// `showMenu` 的模态遮罩：
///
/// * 任意时刻全局仅一个菜单——[ContextMenuController.show] 内部会先
///   `removeAny()`。因此菜单已弹出时再次右键其他条目，同一次点击即可关闭
///   旧菜单并打开新菜单（与 Obsidian 等原生行为一致）。
/// * [TapRegion] 在点击卡片之外时关闭菜单，但不消费该次指针——落点之下的
///   目标仍会收到它（例如目录行收到右键后弹出新菜单）。
///
/// 样式与 [LoreTheme] 的 `popupMenuTheme` / `menuTheme` 保持一致。
void showLoreContextMenu({
  required BuildContext context,
  required Offset position,
  required List<LoreContextMenuItem> items,
}) {
  if (items.isEmpty) {
    return;
  }
  // Escape 关闭菜单。用全局键盘监听而非 Focus，避免抢走编辑器等控件的焦点；
  // 菜单以任何方式移除（Escape/点外/点条目/dispose）时经 onRemove 注销监听。
  bool onKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      ContextMenuController.removeAny();
      return true;
    }
    return false;
  }

  HardwareKeyboard.instance.addHandler(onKeyEvent);
  ContextMenuController(
    onRemove: () => HardwareKeyboard.instance.removeHandler(onKeyEvent),
  ).show(
    context: context,
    contextMenuBuilder: (_) =>
        _LoreContextMenuOverlay(position: position, items: items),
  );
}

/// 菜单覆盖层：在触发坐标处定位菜单卡片，并把屏幕边界夹紧，避免溢出。
class _LoreContextMenuOverlay extends StatelessWidget {
  const _LoreContextMenuOverlay({required this.position, required this.items});

  final Offset position;
  final List<LoreContextMenuItem> items;

  /// 菜单最大宽度，用于在屏幕边缘夹紧定位（实际宽度按内容测量，见卡片层）。
  static const double _menuMaxWidth = 200;
  // 与卡片 SingleChildScrollView 的纵向内边距（5*2）保持一致，用于估算自然高度。
  static const double _verticalPadding = 5;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxLeft = (constraints.maxWidth - _menuMaxWidth).clamp(
          0.0,
          constraints.maxWidth,
        );
        final left = position.dx.clamp(0.0, maxLeft);
        // 估算菜单自然高度：下方放不下时翻到光标上方，避免在屏幕/窗口底部
        // 被夹成只剩一两行甚至不可见（原生菜单同样会向上翻转）。
        final itemHeight = LoreMenuMetrics.itemHeight(defaultTargetPlatform);
        final naturalHeight = items.length * itemHeight + _verticalPadding * 2;
        var top = position.dy;
        if (top + naturalHeight > constraints.maxHeight) {
          top = (position.dy - naturalHeight).clamp(0.0, constraints.maxHeight);
        }
        final maxMenuHeight = (constraints.maxHeight - top).clamp(
          0.0,
          constraints.maxHeight,
        );
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: _LoreContextMenuCard(
                maxHeight: maxMenuHeight,
                items: items,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LoreContextMenuCard extends StatelessWidget {
  const _LoreContextMenuCard({required this.maxHeight, required this.items});

  final double maxHeight;
  final List<LoreContextMenuItem> items;

  static const double _minWidth = 140;
  static const double _maxWidth = 200;
  static const double _horizontalPadding = 14; // 菜单项左右内边距
  // 内容宽度余量：覆盖卡片描边、子像素舍入以及条目过多时出现的滚动条，
  // 避免最宽标签（如"在 Finder 中显示"）刚好顶到可用宽度而被折成两行。
  static const double _extraWidth = 18;
  static const TextStyle _labelStyle = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w500,
  );

  /// 按最宽标签测量内容宽度（含内边距与余量），夹紧到 [_minWidth,_maxWidth]。
  double _measureWidth(BuildContext context) {
    final direction = Directionality.of(context);
    var widest = 0.0;
    for (final item in items) {
      final painter = TextPainter(
        text: TextSpan(text: item.label, style: _labelStyle),
        textDirection: direction,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      if (width > widest) {
        widest = width;
      }
    }
    return (widest + _horizontalPadding * 2 + _extraWidth).clamp(
      _minWidth,
      _maxWidth,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final width = _measureWidth(context);
    return TapRegion(
      // 显式不消费外部指针：落点下的目标（如目录行）仍收到该次右键，从而
      // 实现"菜单已弹出时右键其他条目，一次点击即关旧菜单开新菜单"。
      // 不要改为 true——那会破坏这一核心行为。
      consumeOutsideTaps: false,
      onTapOutside: (_) => ContextMenuController.removeAny(),
      child: Material(
        color: colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shadowColor: colorScheme.shadow.withValues(alpha: 0.16),
        elevation: 6,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        child: SizedBox(
          width: width,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final item in items)
                    _LoreContextMenuItemView(item: item),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoreContextMenuItemView extends StatelessWidget {
  const _LoreContextMenuItemView({required this.item});

  final LoreContextMenuItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final enabled = item.enabled;
    final color = !enabled
        ? colorScheme.onSurface.withValues(alpha: 0.38)
        : item.destructive
        ? colorScheme.error
        : colorScheme.onSurface;
    return InkWell(
      onTap: enabled
          ? () {
              ContextMenuController.removeAny();
              item.onTap();
            }
          : null,
      child: Container(
        constraints: BoxConstraints(
          minHeight: LoreMenuMetrics.itemHeight(defaultTargetPlatform),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Text(
          item.label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ),
    );
  }
}
