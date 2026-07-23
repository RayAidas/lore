import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lore_domain/lore_domain.dart';

/// 在窗口内容最底层渲染用户选中的背景图片。
final class AppBackground extends StatelessWidget {
  const AppBackground({
    required this.preferences,
    required this.child,
    super.key,
  });

  final AppPreferences preferences;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final imagePath = preferences.backgroundImagePath;
    final hasImage = imagePath != null && imagePath.isNotEmpty;
    return Stack(
      fit: StackFit.expand,
      children: [
        // 底色铺底：仅在启用图片背景时绘制，避免图片加载/解码空窗期露出前景
        // 内容背后的透明；无选中图时不画任何层，由 MaterialApp 的 surface 色铺底。
        if (hasImage)
          ColoredBox(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 1),
          ),
        if (hasImage)
          Image.file(
            File(imagePath),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => const SizedBox(),
          ),
        if (hasImage && preferences.backgroundImageDimness > 0)
          ColoredBox(
            color: Colors.black.withValues(
              alpha: preferences.backgroundImageDimness,
            ),
          ),
        child,
      ],
    );
  }
}
