import 'package:flutter/foundation.dart';

/// 是否运行在支持分屏等桌面级交互的平台（macOS/Windows/Linux）。
///
/// 集中一处定义，供 workspace 各处（页面布局、编辑分组、标签右键菜单的
/// 分屏项）共用——避免 `defaultTargetPlatform` 的 switch 在多文件复制，
/// 未来调整平台规则只改这里。
bool get supportsDesktopSplit => switch (defaultTargetPlatform) {
  TargetPlatform.macOS ||
  TargetPlatform.windows ||
  TargetPlatform.linux => true,
  _ => false,
};
