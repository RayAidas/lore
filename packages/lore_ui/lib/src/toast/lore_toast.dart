import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/lore_theme.dart';

/// Toast 语义类型，决定图标徽章配色与默认图标。
enum LoreToastType { success, info, warning, error }

/// Lore 全局轻量提示：主题卡片式、顶部居中。
///
/// 基于 [Overlay] 悬浮，不依赖 [Scaffold]、不挤占布局；在 light / sepia /
/// dark 三套主题下随 [ColorScheme] 自动协调。同一时刻只保留一个 toast，
/// 再次 [show] 会先移除上一个，避免堆叠遮挡；点击可提前关闭。
abstract final class LoreToast {
  LoreToast._();

  /// 当前正显示的 toast（全局唯一）。
  static OverlayEntry? _current;

  /// [_current] 所属的 Overlay。跨 Overlay（多 navigator、widget tree 重建）
  /// 时据此判断能否安全移除上一条，避免对已失效的 Overlay 操作而抛错。
  static OverlayState? _currentOverlay;

  /// 在 [context] 所属的根 [Overlay] 顶部居中弹出一个 toast。
  ///
  /// 调用方需自行确认 `context.mounted`。取 root overlay，使 toast 盖在
  /// 对话框等其它浮层之上。
  static void show(
    BuildContext context, {
    required String message,
    LoreToastType type = LoreToastType.info,
    Duration duration = const Duration(seconds: 2),
    IconData? icon,
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);

    // 仅当上一条与当前 toast 同属一个 Overlay 时才 remove（安全）；若分属
    // 不同 Overlay（多 navigator，或旧 widget tree 已销毁），直接丢弃引用——
    // 旧 entry 随其所属 Overlay 自行卸载，无需也无法在此 remove。
    if (!identical(_currentOverlay, overlay)) {
      _current = null;
    }
    _current?.remove();
    _current = null;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _LoreToastView(
        message: message,
        type: type,
        icon: icon,
        duration: duration,
        onDismissed: () {
          if (identical(_current, entry)) {
            _current = null;
            _currentOverlay = null;
          }
          if (entry.mounted) {
            entry.remove();
          }
        },
      ),
    );
    _current = entry;
    _currentOverlay = overlay;
    overlay.insert(entry);
  }
}

/// 视觉规格：默认图标 + 图标前景色。
class _ToastSpec {
  const _ToastSpec({required this.defaultIcon, required this.foregroundColor});

  final IconData defaultIcon;
  final Color foregroundColor;
}

_ToastSpec _specFor(LoreToastType type, ColorScheme colorScheme) {
  switch (type) {
    case LoreToastType.success:
      return _ToastSpec(
        defaultIcon: Icons.check_circle_rounded,
        foregroundColor: colorScheme.successForeground,
      );
    case LoreToastType.warning:
      return _ToastSpec(
        defaultIcon: Icons.warning_amber_rounded,
        foregroundColor: colorScheme.warningForeground,
      );
    case LoreToastType.error:
      return _ToastSpec(
        defaultIcon: Icons.error_outline_rounded,
        foregroundColor: colorScheme.error,
      );
    case LoreToastType.info:
      return _ToastSpec(
        defaultIcon: Icons.info_outline_rounded,
        foregroundColor: colorScheme.primary,
      );
  }
}

class _LoreToastView extends StatefulWidget {
  const _LoreToastView({
    required this.message,
    required this.type,
    required this.icon,
    required this.duration,
    required this.onDismissed,
  });

  final String message;
  final LoreToastType type;
  final IconData? icon;
  final Duration duration;
  final VoidCallback onDismissed;

  @override
  State<_LoreToastView> createState() => _LoreToastViewState();
}

class _LoreToastViewState extends State<_LoreToastView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  // 自动消失计时器；dispose 时取消，避免 widget 树卸载后残留 pending timer。
  Timer? _timer;
  // 是否已进入退场流程，防止 timer 与 tap 几乎同时触发 _dismiss 造成二次调用。
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
    _timer = Timer(widget.duration, _dismiss);
  }

  void _dismiss() {
    if (!mounted || _dismissing) {
      return;
    }
    _dismissing = true;
    _timer?.cancel();
    _controller.reverse().whenComplete(() {
      if (mounted) {
        widget.onDismissed();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return Positioned(
      top: topInset + 28,
      left: 0,
      right: 0,
      child: Center(
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: _LoreToastCard(
              message: widget.message,
              type: widget.type,
              icon: widget.icon,
              onTap: _dismiss,
            ),
          ),
        ),
      ),
    );
  }
}

class _LoreToastCard extends StatelessWidget {
  const _LoreToastCard({
    required this.message,
    required this.type,
    required this.icon,
    required this.onTap,
  });

  final String message;
  final LoreToastType type;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final spec = _specFor(type, colorScheme);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: colorScheme.outlineVariant),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withValues(alpha: 0.14),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon ?? spec.defaultIcon,
                    size: 18,
                    color: spec.foregroundColor,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 13.5,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
