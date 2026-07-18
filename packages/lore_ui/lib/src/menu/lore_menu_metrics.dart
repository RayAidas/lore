import 'package:flutter/material.dart';

abstract final class LoreMenuMetrics {
  static double itemHeight(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => 34,
      TargetPlatform.android ||
      TargetPlatform.fuchsia ||
      TargetPlatform.iOS => 48,
    };
  }

  static MaterialTapTargetSize tapTargetSize(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => MaterialTapTargetSize.shrinkWrap,
      TargetPlatform.android ||
      TargetPlatform.fuchsia ||
      TargetPlatform.iOS => MaterialTapTargetSize.padded,
    };
  }
}
