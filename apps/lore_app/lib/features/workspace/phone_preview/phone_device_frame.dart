import 'package:flutter/material.dart';

import 'phone_device.dart';

/// 手机设备外框：圆角机身 + 屏幕 + 顶部按 [PhoneFrameStyle] 绘制的开孔 + 伪状态栏。
///
/// [child] 渲染在屏幕区域内，按设备逻辑尺寸（[PhoneDevice.width] /
/// [PhoneDevice.height]）布局；外层用 [FittedBox] 把整台手机等比缩放进预览面板。
final class PhoneDeviceFrame extends StatelessWidget {
  const PhoneDeviceFrame({
    required this.device,
    required this.frameStyle,
    required this.child,
    super.key,
  });

  final PhoneDevice device;
  final PhoneFrameStyle frameStyle;

  /// 屏幕内容（标题 + 正文等）。
  final Widget child;

  /// 机身边框厚度。
  static const double bezel = 14;

  /// 机身外圆角。
  static const double frameRadius = 46;

  /// 屏幕内圆角。
  static const double screenRadius = 34;

  /// 伪状态栏高度（屏幕内顶部，时间 / 信号 / 电量 + 开孔区域）。
  ///
  /// 取 38：容纳灵动岛（top 8 + 高 30 = 38）完整落在状态栏内，不压到正文。
  static const double statusBarHeight = 38;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final frameColor = cs.onSurface.withValues(alpha: 0.85);

    return Container(
      width: device.width + bezel * 2,
      height: device.height + bezel * 2,
      decoration: BoxDecoration(
        color: frameColor,
        borderRadius: BorderRadius.circular(frameRadius),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.28),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: bezel,
            top: bezel,
            child: Container(
              width: device.width,
              height: device.height,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                // 强制不透明：图片背景模式下 withSurfaceOpacity 会把 cs.surface
                // 调成半透明（让背景图透出），但屏幕背后是机身（onSurface@0.85
                // 的深色），半透明会透出机身、使屏幕发黑。手机屏幕是设备实体，
                // 应保持不透明，故用 alpha=1 还原原始阅读底色。
                color: cs.surface.withValues(alpha: 1),
                borderRadius: BorderRadius.circular(screenRadius),
              ),
              child: Column(
                children: [
                  _PhoneStatusBar(frameStyle: frameStyle),
                  Expanded(child: child),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 伪状态栏：左侧时间、右侧信号 / Wi-Fi / 电量，顶部中央按外形绘制开孔。
final class _PhoneStatusBar extends StatelessWidget {
  const _PhoneStatusBar({required this.frameStyle});

  final PhoneFrameStyle frameStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final textStyle = theme.textTheme.labelSmall?.copyWith(
      color: cs.onSurface,
      fontWeight: FontWeight.w600,
      fontSize: 12,
    );
    final iconColor = cs.onSurface.withValues(alpha: 0.85);
    return SizedBox(
      height: PhoneDeviceFrame.statusBarHeight,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Row(
              children: [
                Text('9:41', style: textStyle),
                const Spacer(),
                Icon(Icons.signal_cellular_alt, size: 13, color: iconColor),
                const SizedBox(width: 5),
                Icon(Icons.wifi, size: 13, color: iconColor),
                const SizedBox(width: 5),
                _BatteryGlyph(color: iconColor),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: _PhoneFrameCutout(
              frameStyle: frameStyle,
              strokeColor: cs.outlineVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 电池图形：手绘机身 + 端帽 + 满电量填充，避免依赖可能弃用的 Material 电池图标。
final class _BatteryGlyph extends StatelessWidget {
  const _BatteryGlyph({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 12,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 机身外框。
          Container(
            width: 19,
            height: 11,
            decoration: BoxDecoration(
              border: Border.all(color: color, width: 1),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          // 电量填充（满）。
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Container(
                width: 13,
                height: 7,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            ),
          ),
          // 正极端帽。
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              width: 2,
              height: 5,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 屏幕顶部开孔（刘海 / 灵动岛 / 挖孔），按 [frameStyle] 绘制；直屏不绘制。
final class _PhoneFrameCutout extends StatelessWidget {
  const _PhoneFrameCutout({
    required this.frameStyle,
    required this.strokeColor,
  });

  final PhoneFrameStyle frameStyle;

  /// 开孔描边色：暗色主题下黑开孔与暗屏幕对比不足，靠这层描边露出轮廓。
  final Color strokeColor;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(double.infinity, PhoneDeviceFrame.statusBarHeight),
      painter: _FrameCutoutPainter(
        frameStyle: frameStyle,
        strokeColor: strokeColor,
      ),
    );
  }
}

final class _FrameCutoutPainter extends CustomPainter {
  _FrameCutoutPainter({required this.frameStyle, required this.strokeColor});

  final PhoneFrameStyle frameStyle;

  /// 开孔描边色，与屏幕底色形成可见对比（暗色主题下尤甚）。
  final Color strokeColor;

  @override
  void paint(Canvas canvas, Size size) {
    // 实体黑色填充（真实开孔观感）。
    final fill = Paint()..color = const Color(0xFF000000);
    // 描边：暗色主题下黑开孔与暗屏幕几乎无对比，靠这层轮廓线让外形可见。
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = strokeColor;
    final cx = size.width / 2;
    switch (frameStyle) {
      case PhoneFrameStyle.flat:
        return;
      case PhoneFrameStyle.notch:
        const w = 150.0;
        const h = 22.0;
        // 仅底部两角圆角，呈「从顶边凹下」的刘海。
        final rrect = RRect.fromRectAndCorners(
          Rect.fromLTWH(cx - w / 2, 0, w, h),
          bottomLeft: const Radius.circular(12),
          bottomRight: const Radius.circular(12),
        );
        canvas.drawRRect(rrect, fill);
        canvas.drawRRect(rrect, stroke);
      case PhoneFrameStyle.dynamicIsland:
        const w = 112.0;
        const h = 30.0;
        // 悬浮于顶边下方的药丸。
        final rrect = RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - w / 2, 8, w, h),
          const Radius.circular(15),
        );
        canvas.drawRRect(rrect, fill);
        canvas.drawRRect(rrect, stroke);
      case PhoneFrameStyle.punchHole:
        final center = Offset(cx, 15);
        canvas.drawCircle(center, 6.5, fill);
        canvas.drawCircle(center, 6.5, stroke);
    }
  }

  @override
  bool shouldRepaint(_FrameCutoutPainter oldDelegate) =>
      oldDelegate.frameStyle != frameStyle ||
      oldDelegate.strokeColor != strokeColor;
}
