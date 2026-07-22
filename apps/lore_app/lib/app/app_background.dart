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
    final imageMode = preferences.backgroundMode == AppBackgroundMode.image;
    final hasImage = imageMode && imagePath != null && imagePath.isNotEmpty;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (imageMode)
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
