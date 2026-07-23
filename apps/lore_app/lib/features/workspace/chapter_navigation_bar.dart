import 'package:flutter/material.dart';
import 'package:lore_application/lore_application.dart';

import 'chapter_navigation.dart';
import 'library_failure_snackbar.dart';
import 'workspace_controller.dart';

/// 编辑器状态栏内的章节导航条：上一章 / 当前位置·总数 / 下一章 / 新建下一章。
///
/// 仅对注册章节文档（[OpenDocument.chapterNumber] 非空且能在结构树命中）渲染。
/// 「新建下一章」在当前章所在卷末尾追加（正文根级章节则加到 body 下）；
/// ◁/▷ 按全书阅读顺序跳转（跨卷）。让写了几十章、卷节点滚出视野后仍能就地
/// 续写与翻章，不必回到侧栏目录树找卷。
///
/// 依赖外层（[DocumentPane] 状态栏）已订阅 controller + document：结构变更、
/// 保存、切章都会触发重建，导航位置随之刷新。
class ChapterNavigationBar extends StatefulWidget {
  const ChapterNavigationBar({
    required this.controller,
    required this.document,
    super.key,
  });

  final WorkspaceController controller;
  final OpenDocument document;

  @override
  State<ChapterNavigationBar> createState() => _ChapterNavigationBarState();
}

class _ChapterNavigationBarState extends State<ChapterNavigationBar> {
  ChapterNavigation? get _navigation {
    // 直接用 chapterNodeForPath 返回的 (novelId, nodeId) 元组：两者来自同一次
    // 匹配，保证小说与节点对齐——避免 novelIdForPath 的前缀命中与章节命中
    // 分属不同小说时，novel 与 node 不一致导致导航条静默消失。
    final hit = widget.controller.chapterNodeForPath(
      widget.document.relativePath,
    );
    if (hit == null) {
      return null;
    }
    final novel = widget.controller.novels
        .where((snapshot) => snapshot.metadata.id == hit.novelId)
        .firstOrNull;
    if (novel == null) {
      return null;
    }
    final node = novel.contentTree.nodeById(hit.nodeId);
    if (node == null) {
      return null;
    }
    return computeChapterNavigation(novel, node);
  }

  Future<void> _createNext() async {
    final nav = _navigation;
    if (nav == null) {
      return;
    }
    try {
      await widget.controller.createChapter(
        nav.novelId,
        volumeId: nav.volumeId,
      );
    } on LibraryOperationException catch (error) {
      // 结构服务不可用 / 写盘失败等：复用全局失败提示，避免点击无反馈。
      if (!mounted) {
        return;
      }
      showLibraryFailure(context, error.failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nav = _navigation;
    if (nav == null) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final base = theme.textTheme.bodySmall ?? const TextStyle();
    final muted = base.copyWith(color: cs.onSurfaceVariant);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _NavArrow(
          icon: Icons.chevron_left_rounded,
          tooltip: '上一章',
          enabled: nav.hasPrevious,
          onTap: () => widget.controller.openPath(nav.previousPath!),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text.rich(
            TextSpan(
              style: muted,
              children: [
                TextSpan(
                  text: '${nav.index + 1}',
                  style: base.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(text: ' / ${nav.total}'),
              ],
            ),
          ),
        ),
        _NavArrow(
          icon: Icons.chevron_right_rounded,
          tooltip: '下一章',
          enabled: nav.hasNext,
          onTap: () => widget.controller.openPath(nav.nextPath!),
        ),
        const SizedBox(width: 8),
        // 「新建」与翻章是不同类操作，用主题色（而非填充背景）轻量区分主操作，
        // 保持与状态栏其余扁平图标/文本一致的视觉权重，不喧宾夺主。
        IconButton(
          tooltip: '新建下一章（当前卷，自动打开）',
          icon: const Icon(Icons.add_rounded, size: 18),
          color: cs.primary,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          padding: EdgeInsets.zero,
          onPressed: _createNext,
        ),
      ],
    );
  }
}

/// 紧凑导航箭头：禁用态由 IconButton 默认置灰，启用态走标准涟漪。
class _NavArrow extends StatelessWidget {
  const _NavArrow({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 18),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      padding: EdgeInsets.zero,
      onPressed: enabled ? onTap : null,
    );
  }
}
