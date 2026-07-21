import 'package:flutter/material.dart';

/// 自适应辅助面板的宽屏断点：不小于此宽度走居中对话框，否则走底部 sheet。
const double lorePanelWideBreakpoint = 600;

/// 自适应辅助面板的默认最大宽度。
const double lorePanelDefaultMaxWidth = 560;

/// 桌面面板左右留出的边距，让面板悬浮、背景透出工作区。
const double _lorePanelDesktopMargin = 64;

/// 以自适应形态呈现一个辅助面板（设置 / 回收站等）。
///
/// 与全屏路由不同，面板不会接管整个窗口：宽屏（≥ [lorePanelWideBreakpoint]）
/// 下为居中、宽度固定的悬浮卡片，窄屏下为底部 [BottomSheet]。写作工作区保留
/// 在背后，符合"临时工具"心智；同时自然获得点遮罩 / Esc / 标题栏关闭按钮三种
/// 关闭方式。
///
/// 宽屏下用 `showDialog` + [Center] 自行承载面板，**刻意不使用 [Dialog]
/// widget**：Material 3 的 [Dialog] 内部会对子节点套一个隐藏的最大宽度约束
/// （约 560），会把传入的更大宽度（如设置面板的 760）压缩成 560。改用 [Center]
/// 让 [_LorePanel] 用 tight 约束自行决定宽度，即可绕开该限制。[child] 自行
/// 负责可滚动（如 [ListView]）；面板通过最大高度约束保证内容不溢出窗口。
/// [subtitle] 可选，渲染为标题下方的说明小字。
Future<T?> showLorePanelSheet<T>({
  required BuildContext context,
  required String title,
  required Widget child,
  IconData? icon,
  String? subtitle,
  double maxWidth = lorePanelDefaultMaxWidth,
  double desktopMaxHeightFactor = 0.85,
  bool barrierDismissable = true,
}) {
  final media = MediaQuery.sizeOf(context);
  final isWide = media.width >= lorePanelWideBreakpoint;
  if (isWide) {
    final width = (media.width - _lorePanelDesktopMargin).clamp(
      320.0,
      maxWidth,
    );
    final maxHeight = media.height * desktopMaxHeightFactor;
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissable,
      builder: (_) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 56),
          child: _LorePanel(
            title: title,
            subtitle: subtitle,
            icon: icon,
            width: width,
            maxHeight: maxHeight,
            child: child,
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    isDismissible: barrierDismissable,
    constraints: BoxConstraints(maxWidth: maxWidth),
    builder: (ctx) => _LorePanel(
      title: title,
      subtitle: subtitle,
      icon: icon,
      // 窄屏 sheet 填满 sheet 宽度，仅限最大高度，顶部留出工作区背景。
      width: null,
      maxHeight: MediaQuery.sizeOf(ctx).height * desktopMaxHeightFactor,
      child: child,
    ),
  );
}

/// 面板的统一外观：悬浮卡片容器 + 标题栏（图标徽标 + 标题/副标题 + 关闭）+ 内容。
///
/// [width] 非 null 时（桌面）用 tight 约束固定面板宽度；为 null 时（底部 sheet）
/// 填满父约束。容器用 [Container]（绘制背景/边框/阴影）+ [ClipRRect]（裁剪内容到
/// 圆角，但不裁剪外部阴影）。内部 [Column] 设 `crossAxisAlignment.stretch`，
/// 使标题与内容都填满面板宽度——否则 loose 约束下 Column 会 shrink-wrap 成
/// 过窄的一列。
class _LorePanel extends StatelessWidget {
  const _LorePanel({
    required this.title,
    required this.child,
    required this.maxHeight,
    required this.width,
    this.icon,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final IconData? icon;
  final double? width;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final constraints = width == null
        ? BoxConstraints(maxHeight: maxHeight)
        : BoxConstraints.tightFor(width: width).copyWith(maxHeight: maxHeight);
    return ConstrainedBox(
      constraints: constraints,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 40,
              offset: const Offset(0, 16),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          // 提供 Material 祖先：面板内的 DropdownButton/Switch/Slider 等需要它。
          // 透明、不裁剪，背景与阴影均由外层 Container 的 decoration 负责。
          color: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 12, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (icon != null) ...[
                        Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            icon,
                            size: 20,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 14),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                            ),
                            if (subtitle != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  subtitle!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ],
                  ),
                ),
                Flexible(child: child),
              ],
            ),
          ), // ClipRRect
        ), // Material
      ), // Container
    );
  }
}
