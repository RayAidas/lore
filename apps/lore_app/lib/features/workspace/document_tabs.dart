import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'workspace_controller.dart';

/// 文档标签条：水平滚动，展示已打开文档，支持激活与关闭。
///
/// 采用现代药丸式（pill）样式：每个标签为全圆角胶囊，随内容撑开（上限
/// [_TabChip.maxWidth]），激活态以中性背景填充，不再使用顶部指示条，靠背景
/// 与文字/图标颜色区分当前页。字重在激活态保持恒定，避免点击时因加粗导致
/// 宽度跳动。文件名超长时省略号截断，hover 整个标签显示完整名。
final class DocumentTabs extends StatelessWidget {
  const DocumentTabs({
    required this.controller,
    required this.onClose,
    super.key,
  });

  final WorkspaceController controller;
  final Future<void> Function(WorkspaceTab tab) onClose;

  static const double barHeight = 38;

  @override
  Widget build(BuildContext context) {
    // 监听 controller：tabs 增删与 activePath 切换时整体重建，使本组件可脱离
    // 外层 controller 监听独立使用。单 tab 的细粒度刷新仍由下方
    // ListenableBuilder(tab) 负责。
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final colorScheme = Theme.of(context).colorScheme;
        if (controller.tabs.isEmpty) {
          return ColoredBox(
            color: colorScheme.surfaceContainerLowest,
            child: const SizedBox(height: barHeight),
          );
        }
        return ColoredBox(
          color: colorScheme.surfaceContainerLowest,
          child: SizedBox(
            height: barHeight,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              scrollDirection: Axis.horizontal,
              itemCount: controller.tabs.length,
              itemBuilder: (context, index) {
                final tab = controller.tabs[index];
                return ListenableBuilder(
                  listenable: tab,
                  builder: (context, _) {
                    final active = controller.activePath == tab.relativePath;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 2,
                      ),
                      child: _TabChip(
                        tab: tab,
                        active: active,
                        onTap: () => unawaited(controller.activateTab(tab)),
                        onClose: () => unawaited(onClose(tab)),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.tab,
    required this.active,
    required this.onTap,
    required this.onClose,
  });

  final WorkspaceTab tab;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;

  /// 标签内容区（图标 + 文件名 + 关闭按钮）的最大宽度（像素）。
  static const double maxWidth = 220;

  static const BorderRadius _borderRadius = BorderRadius.all(
    Radius.circular(7),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isMarkdown = p.extension(tab.name).toLowerCase() == '.md';
    // 与左侧目录树一致：文本文件隐藏 `.txt` 后缀，Markdown 等保留扩展名。
    final displayName = _tabDisplayName(tab.name);

    return Tooltip(
      message: tab.name,
      excludeFromSemantics: true,
      waitDuration: const Duration(milliseconds: 500),
      child: Semantics(
        label: displayName,
        selected: active,
        button: true,
        child: Material(
          color: active ? colorScheme.surfaceContainerLow : Colors.transparent,
          borderRadius: _borderRadius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            borderRadius: _borderRadius,
            child: Container(
              constraints: const BoxConstraints(maxWidth: maxWidth),
              padding: const EdgeInsets.only(left: 10, right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isMarkdown
                        ? Icons.description_outlined
                        : Icons.text_snippet_outlined,
                    size: 15,
                    color: active
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: active
                            ? colorScheme.onSurface
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (tab.hasUnsavedChanges)
                    Padding(
                      padding: const EdgeInsets.only(left: 6, right: 2),
                      child: Icon(
                        Icons.circle,
                        size: 7,
                        color: colorScheme.primary,
                      ),
                    ),
                  _TabCloseButton(onPressed: onClose),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 紧凑的圆形关闭按钮：24×24 命中区，13px 图标，
/// hover 时显示淡灰背景与「关闭」提示。
class _TabCloseButton extends StatelessWidget {
  const _TabCloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: '关闭',
      child: Tooltip(
        message: '关闭',
        excludeFromSemantics: true,
        waitDuration: const Duration(milliseconds: 500),
        child: SizedBox(
          width: 24,
          height: 24,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(5),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(5),
              child: const Center(child: Icon(Icons.close_rounded, size: 13)),
            ),
          ),
        ),
      ),
    );
  }
}

const _txtExtension = '.txt';

/// 标签展示名：与目录树 `_treeDisplayName` 一致地剥掉 `.txt` 后缀（大小写
/// 不敏感），其余文件名原样返回。
String _tabDisplayName(String name) {
  if (name.length > _txtExtension.length &&
      name.toLowerCase().endsWith(_txtExtension)) {
    return name.substring(0, name.length - _txtExtension.length);
  }
  return name;
}
