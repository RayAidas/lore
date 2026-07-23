import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_editor/lore_editor.dart';
import 'package:lore_ui/lore_ui.dart';

import '../preferences/font_options.dart';
import '../preferences/preferences_providers.dart';
import '../library/library_providers.dart';
import 'chapter_navigation_bar.dart';
import 'chapter_title_bar.dart';
import 'history_diff_mode.dart';
import 'history_diff_view.dart';
import 'library_failure_snackbar.dart';
import 'local_markdown_image.dart';
import 'open_document_extensions.dart';
import 'workspace_controller.dart';
import 'workspace_metrics.dart';

/// 文档编辑/预览主面板：工具条 + 冲突/错误横幅 + 编辑器或预览 + 状态栏。
final class DocumentPane extends ConsumerStatefulWidget {
  const DocumentPane({
    required this.controller,
    required this.document,
    required this.session,
    required this.onReloadConflict,
    this.onToggleFullscreen,
    super.key,
  });

  final WorkspaceController controller;
  final OpenDocument document;
  final LibrarySession session;
  final VoidCallback onReloadConflict;

  /// 非空时在工具条末尾渲染「退出全屏」按钮。仅在页面级全屏模式下传入；
  /// 普通模式为 null（不显示），保证全屏退出有可见入口。
  final VoidCallback? onToggleFullscreen;

  @override
  ConsumerState<DocumentPane> createState() => _DocumentPaneState();
}

final class _DocumentPaneState extends ConsumerState<DocumentPane> {
  /// 章节标题栏按回车后聚焦正文的入口节点；交给 [LoreLargeTextEditor] 转发
  /// 到首个段落块。
  final FocusNode _bodyFocusNode = FocusNode();

  /// 同时监听文档与控制器：文档变化（保存状态等）与控制器变化（diff 状态）
  /// 都需触发重绘。
  late final Listenable _listenable = Listenable.merge([
    widget.document,
    widget.controller,
  ]);

  @override
  void dispose() {
    _bodyFocusNode.dispose();
    super.dispose();
  }

  /// 选中文字后右键(macOS)/长按(Android)触发:色块行上色、复制、取消高亮。
  void _showEditorContextMenu(Offset position) {
    final controller = document.editorController;
    if (controller is! LoreLargeTextController) return;
    final selection = controller.selection;
    final hasSelection = selection.isValid && !selection.isCollapsed;
    final prefs =
        ref.read(appPreferencesProvider).value ?? AppPreferences.defaults();
    final palette = prefs.highlightPalette;
    final intersecting = hasSelection
        ? controller.highlightsIntersecting(selection.start, selection.end)
        : const <Highlight>[];
    showLoreContextMenu(
      context: context,
      position: position,
      items: [
        LoreContextMenuItem(
          label: '',
          onTap: () {},
          // 色块行:首项为"不高亮"(空心 ×,仅选中段含高亮时可点),其后为调色板颜色。
          // i==0 → 不高亮;i>0 → palette[i-1]。共 palette.length+1 个色块一行。
          custom: Opacity(
            opacity: hasSelection ? 1.0 : 0.4,
            // FittedBox(scaleDown):色块行超出可用宽时整体缩小而非溢出报错
            // (无障碍字体缩放 / 非整数 DPI 边界防御)。
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i <= palette.length; i++)
                    Padding(
                      padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
                      child: i == 0
                          ? GestureDetector(
                              // 点不高亮先关菜单,与"复制"行为一致。
                              onTap: intersecting.isNotEmpty
                                  ? () {
                                      ContextMenuController.removeAny();
                                      controller.removeHighlightsIntersecting(
                                        selection.start,
                                        selection.end,
                                      );
                                    }
                                  : null,
                              child: Opacity(
                                opacity: intersecting.isNotEmpty ? 1.0 : 0.4,
                                child: Container(
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outline,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.close,
                                    size: 12,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                ),
                              ),
                            )
                          : GestureDetector(
                              onTap: hasSelection
                                  ? () {
                                      ContextMenuController.removeAny();
                                      controller.addHighlight(
                                        selection.start,
                                        selection.end,
                                        palette[i - 1],
                                      );
                                    }
                                  : null,
                              child: Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: Color(palette[i - 1]),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.outlineVariant,
                                  ),
                                ),
                              ),
                            ),
                    ),
                ],
              ),
            ),
          ),
        ),
        LoreContextMenuItem(
          label: '复制',
          enabled: hasSelection,
          onTap: () => _copySelection(controller),
        ),
      ],
    );
  }

  void _copySelection(LoreLargeTextController controller) {
    final selection = controller.selection;
    if (selection.isCollapsed) return;
    Clipboard.setData(
      ClipboardData(
        text: controller.text.substring(selection.start, selection.end),
      ),
    );
  }

  WorkspaceController get controller => widget.controller;
  OpenDocument get document => widget.document;
  LibrarySession get session => widget.session;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _listenable,
      builder: (context, _) => _buildContent(context),
    );
  }

  /// diff 对比视图：替换编辑器内容区。对比工具条（标题 + 内联/并排 + 退出）
  /// + HistoryDiffView（该快照 vs 当前磁盘）。
  Widget _buildDiff(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final target = controller.diffTarget!;
    // diff 跟随编辑器偏好（字体 / 字号 / 行高 / 宽度 / 缩进 / 段距）。_buildDiff 在
    // diff 模式下早返回，不经过 _buildContent 内的 watch，须在此显式订阅，设置变更
    // 才能实时重排对比视图。
    final prefs =
        ref.watch(appPreferencesProvider).value ?? AppPreferences.defaults();
    final editorStyle = _resolveEditorStyle(prefs);
    // 章节文档：把标题首行（`第N章 …` / `# 第N章 …`）与正文拆开——正文单独 diff
    // （apples-to-apples），标题作为独立首块渲染（套标题排版），标题变更（编号 /
    // 副标题 / 重命名）在 unified 下字符级 diff、在 split 下左右各显一侧。章节历史
    // 以稳定 nodeId 落盘，文件重命名不丢历史，故此处按当前路径解析标题即可。
    final isChapter = document.chapterNumber != null;
    final String oldBody;
    final String newBody;
    final String? oldTitle;
    final String? newTitle;
    if (isChapter) {
      final markdown = document.isMarkdown;
      final oldParsed = ChapterTitleText.tryParse(
        target.snapshotText,
        markdown: markdown,
      );
      final newParsed = ChapterTitleText.tryParse(
        document.snapshot.text,
        markdown: markdown,
      );
      oldTitle = oldParsed == null
          ? null
          : ChapterTitleText.titleLine(oldParsed.number, oldParsed.subtitle);
      newTitle = newParsed == null
          ? null
          : ChapterTitleText.titleLine(newParsed.number, newParsed.subtitle);
      oldBody = ChapterTitleText.bodyOf(target.snapshotText);
      newBody = ChapterTitleText.bodyOf(document.snapshot.text);
    } else {
      oldTitle = null;
      newTitle = null;
      oldBody = target.snapshotText;
      newBody = document.snapshot.text;
    }
    final stats = diffCharStats(oldBody, newBody);
    return Column(
      children: [
        // 与编辑态工具行、上方标签行同高（38）。
        Container(
          height: 38,
          color: cs.surface,
          child: Row(
            children: [
              const SizedBox(width: 18),
              Icon(
                Icons.compare_arrows_rounded,
                size: 16,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              // 标题 + 净增删摘要归到左侧（摘要紧跟标题），内联/并排与退出留在右侧。
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        '${target.snapshotTitle}  →  当前',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '+${stats.added}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: diffInsertColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '−${stats.removed}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: diffDeleteColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '内联',
                isSelected: controller.diffMode == DiffViewMode.inline,
                style: _toolbarIconButtonStyle(cs),
                onPressed: () => controller.setDiffMode(DiffViewMode.inline),
                icon: const Icon(Icons.article_outlined, size: 16),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: '并排',
                isSelected: controller.diffMode == DiffViewMode.split,
                style: _toolbarIconButtonStyle(cs),
                onPressed: () => controller.setDiffMode(DiffViewMode.split),
                icon: const Icon(Icons.vertical_split_outlined, size: 16),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: '退出对比',
                style: _toolbarIconButtonStyle(cs),
                onPressed: controller.exitHistoryDiff,
                icon: const Icon(Icons.close_rounded, size: 16),
              ),
              const SizedBox(width: 10),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: HistoryDiffView(
            oldText: oldBody,
            newText: newBody,
            oldTitle: oldTitle,
            newTitle: newTitle,
            mode: controller.diffMode,
            style: editorStyle,
          ),
        ),
      ],
    );
  }

  /// 从应用偏好派生编辑器排版（字体 / 字号 / 行高 / 宽度 / 缩进 / 段距 等）。
  /// 编辑/预览（_buildContent）与历史对比（_buildDiff）共用，保证 diff 与编辑器
  /// 视觉同口径——同一份偏好改一处、两处同变。
  EditorStyle _resolveEditorStyle(AppPreferences prefs) {
    final fontOption = AppFontOptions.resolve(prefs.editorFontFamily);
    return const EditorStyle.defaults().copyWith(
      lineHeight: prefs.editorLineHeight,
      fontSize: prefs.editorFontSize,
      contentWidth: prefs.editorContentWidth,
      fontFamily: fontOption.fontFamily,
      fontFamilyFallback: fontOption.fontFamilyFallback,
      typewriterMode: prefs.typewriterMode,
      focusMode: prefs.focusMode,
      firstLineIndent: prefs.firstLineIndent,
      paragraphSpacing: prefs.paragraphSpacing,
      gridLineMode: prefs.gridLineMode,
    );
  }

  Widget _buildContent(BuildContext context) {
    if (controller.isDiffing(document)) {
      return _buildDiff(context);
    }
    final colorScheme = Theme.of(context).colorScheme;
    final prefs =
        ref.watch(appPreferencesProvider).value ?? AppPreferences.defaults();
    final fontOption = AppFontOptions.resolve(prefs.editorFontFamily);
    final editorStyle = _resolveEditorStyle(prefs);
    final hasTitle = document.chapterNumber != null;
    // .txt 章节走 LoreLargeTextEditor：标题作为编辑器滚动视口的 header 随正文滚动。
    // 其余路径（.md 编辑/预览）的渲染器持有自己的内部滚动控制器，无法注入 header，
    // 标题仍外挂在 Column 顶端（固定）。
    final isLargeTextPath =
        !document.showPreview &&
        document.editorController is LoreLargeTextController;
    ChapterTitleBar buildTitleBar() => ChapterTitleBar(
      // 按文档实例（identity）作 key：副标题→文件名重命名会改变 relativePath，
      // 按路径作 key 会整体重挂载、副标题失焦；按实例作 key 仅在切文档（不同
      // 实例）时重挂载。.txt 路径下标题在编辑器 header 内、编辑器已带同款 key
      // 控制重挂载，此 key 仅对 .md 外挂路径生效。
      key: ValueKey(document),
      chapterNumber: document.chapterNumber!,
      subtitle: document.chapterTitleSubtitle,
      style: editorStyle,
      autofocusSubtitle: document.editorController.text.isEmpty,
      onChanged: (value) =>
          controller.updateChapterTitleSubtitle(document, value),
      onEnter: () {
        document.editorController.selection = const TextSelection.collapsed(
          offset: 0,
        );
        _bodyFocusNode.requestFocus();
      },
    );
    return Column(
      children: [
        // 工具行与上方标签行（DocumentTabs.barHeight = 38）等高，视觉对齐。
        Container(
          height: 38,
          color: colorScheme.surface,
          child: Row(
            children: [
              const SizedBox(width: 18),
              Icon(
                Icons.folder_open_outlined,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  document.relativePath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (document.isMarkdown)
                IconButton(
                  // 图标反映当前模式：编辑态显铅笔、预览态显眼睛（Obsidian 风格）。
                  // tooltip 同时说明当前模式与点击后切换到的模式。
                  tooltip: document.showPreview
                      ? '预览模式（点击切回编辑）'
                      : '编辑模式（点击切换到预览）',
                  isSelected: document.showPreview,
                  style: _toolbarIconButtonStyle(colorScheme),
                  onPressed: () =>
                      controller.setPreview(document, !document.showPreview),
                  icon: Icon(
                    document.showPreview
                        ? Icons.remove_red_eye_outlined
                        : Icons.edit_outlined,
                    size: 16,
                  ),
                ),
              if (!document.isMarkdown) ...[
                IconButton(
                  tooltip: '打字机模式 (Cmd+Shift+T)',
                  isSelected: prefs.typewriterMode,
                  style: _toolbarIconButtonStyle(colorScheme),
                  onPressed: () => ref
                      .read(appPreferencesProvider.notifier)
                      .setTypewriterMode(!prefs.typewriterMode),
                  icon: const Icon(Icons.vertical_align_center, size: 16),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: '专注模式',
                  isSelected: prefs.focusMode,
                  style: _toolbarIconButtonStyle(colorScheme),
                  onPressed: () => ref
                      .read(appPreferencesProvider.notifier)
                      .setFocusMode(!prefs.focusMode),
                  icon: const Icon(Icons.center_focus_strong, size: 16),
                ),
              ],
              if (widget.onToggleFullscreen != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '退出全屏 (Esc)',
                  style: _toolbarIconButtonStyle(colorScheme),
                  onPressed: widget.onToggleFullscreen,
                  icon: const Icon(Icons.fullscreen_exit, size: 16),
                ),
              ],
              const SizedBox(width: 10),
            ],
          ),
        ),
        if (document.saveStatus == DocumentSaveStatus.conflict)
          MaterialBanner(
            content: Text(
              document.sourceMissing
                  ? '原文件已被删除或移动，当前内容仍保留在编辑器中。'
                  : '文件已在 Lore 外部修改，自动保存已暂停。',
            ),
            actions: [
              if (!document.sourceMissing)
                TextButton(
                  onPressed: widget.onReloadConflict,
                  child: const Text('重新加载磁盘版本'),
                ),
              FilledButton.tonal(
                onPressed: () async {
                  try {
                    await controller.saveConflictCopy(document);
                  } on LibraryOperationException catch (error) {
                    if (context.mounted) {
                      showLibraryFailure(context, error.failure);
                    }
                  }
                },
                child: const Text('当前内容另存副本'),
              ),
            ],
          ),
        if (document.saveStatus == DocumentSaveStatus.error)
          MaterialBanner(
            content: Text(document.failure?.message ?? '文档保存失败。'),
            actions: [
              TextButton(
                onPressed: () => unawaited(controller.saveDocument(document)),
                child: const Text('重试'),
              ),
            ],
          ),
        const Divider(height: 1),
        Expanded(
          child: ColoredBox(
            color: colorScheme.surface,
            child: Column(
              children: [
                if (hasTitle && !isLargeTextPath) buildTitleBar(),
                Expanded(
                  child: document.showPreview && document.isMarkdown
                      ? LoreMarkdownPreview(
                          data: document.editorController.text,
                          fontFamily: fontOption.fontFamily,
                          fontFamilyFallback: fontOption.fontFamilyFallback,
                          fontSize: prefs.editorFontSize,
                          lineHeight: prefs.editorLineHeight,
                          imageBuilder: (uri, width, height) =>
                              LocalMarkdownImage(
                                session: session,
                                assetService: ref.watch(
                                  libraryAssetServiceProvider,
                                ),
                                documentPath: document.relativePath,
                                uri: uri,
                                width: width,
                                height: height,
                              ),
                        )
                      : switch (document.editorController) {
                          LoreLargeTextController largeController =>
                            LoreLargeTextEditor(
                              // 按文档实例作 key：仅在切换文档（不同实例）时重挂载，
                              // 副标题重命名（同实例、路径变）时不重挂载，避免失焦。
                              key: ValueKey(document),
                              controller: largeController,
                              scrollController: document.scrollController,
                              style: editorStyle,
                              // 章节标题作为滚动视口首个 sliver，随正文一起滚动。
                              header: hasTitle ? buildTitleBar() : null,
                              // 有标题栏时去掉正文顶部留白，间距由标题栏底 padding 控制。
                              topPadding: hasTitle ? 0 : 42,
                              focusNode: hasTitle ? _bodyFocusNode : null,
                              // 章节正文首段自动补两字缩进（受 firstLineIndent 偏好控制）。
                              indentFirstParagraph: hasTitle,
                              autofocus:
                                  !hasTitle ||
                                  document.editorController.text.isNotEmpty,
                              onContextMenu: _showEditorContextMenu,
                            ),
                          LoreTextController textController => LoreTextEditor(
                            key: ValueKey(document),
                            controller: textController,
                            scrollController: document.scrollController,
                            style: editorStyle,
                            // 章节标题文档：标题栏回车后聚焦正文字段。
                            focusNode: hasTitle ? _bodyFocusNode : null,
                            autofocus:
                                !hasTitle ||
                                document.editorController.text.isNotEmpty,
                          ),
                          _ => const SizedBox.shrink(),
                        },
                ),
              ],
            ),
          ),
        ),
        Container(
          key: const ValueKey('document-status-bar'),
          height: workspaceChromeBarHeight,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            border: Border(
              top: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            children: [
              // 仅监听编辑器控制器：选区变化只重建这个标签，不波及编辑器本体。
              ListenableBuilder(
                listenable: document.editorController,
                builder: (context, _) {
                  // 预览模式下不可见选区，编辑态遗留的 selection 不应显示选中数。
                  if (document.showPreview) {
                    return _DocumentCharCount(
                      total: document.characterCount,
                      selected: 0,
                    );
                  }
                  final selection = document.editorController.selection;
                  final hasSelection =
                      selection.isValid && !selection.isCollapsed;
                  final selected = hasSelection
                      ? document.editorController.characterCountInRange(
                          selection.start,
                          selection.end,
                        )
                      : 0;
                  return _DocumentCharCount(
                    total: document.characterCount,
                    selected: selected,
                  );
                },
              ),
              const Spacer(),
              if (document.chapterNumber != null) ...[
                ChapterNavigationBar(
                  controller: controller,
                  document: document,
                ),
                const SizedBox(width: 12),
              ],
              Icon(
                document.saveStatusIcon,
                size: 14,
                color: document.saveStatusColor(context),
              ),
              const SizedBox(width: 6),
              Text(
                document.saveStatusText,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: document.saveStatusColor(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 状态栏字数标签：无选区显示「{total} 字」；有选区显示「{selected}/{total} 字」，
/// 选中字数用主题色 + 半粗体与总数区分，与编辑器字数同口径（全选时 selected == total）。
final class _DocumentCharCount extends StatelessWidget {
  const _DocumentCharCount({required this.total, required this.selected});

  final int total;
  final int selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final base = theme.textTheme.bodySmall ?? const TextStyle();
    final muted = base.copyWith(color: colorScheme.onSurfaceVariant);
    if (selected <= 0) {
      return Text('$total 字', style: muted);
    }
    return Text.rich(
      TextSpan(
        style: muted,
        children: [
          TextSpan(
            text: '$selected',
            style: base.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(text: '/$total 字'),
        ],
      ),
    );
  }
}

/// 文档工具行图标按钮样式：紧凑方形命中区（30×30），避免默认 48×48 最小
/// 尺寸撑高仅 38px 的工具行。打字机/专注/退出全屏共用。
///
/// 选中态（打字机/专注开启，IconButton 由 isSelected 推出 WidgetState.selected）
/// 以两层弱信号叠成清晰开/关：图标转 onSurface 实色 + 一层 primary@16% 淡底色；
/// 未选中为 onSurfaceVariant 淡色、透明底。悬停反馈交给 IconButton 默认 overlay。
/// 按钮间在调用处留 SizedBox(width:4) 间隔，避免两个都选中时淡底色边界相连。
ButtonStyle _toolbarIconButtonStyle(ColorScheme colorScheme) => ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(Size.square(30)),
  maximumSize: const WidgetStatePropertyAll(Size.square(30)),
  padding: const WidgetStatePropertyAll(EdgeInsets.zero),
  shape: const WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(7))),
  ),
  foregroundColor: WidgetStateProperty.resolveWith((states) {
    if (states.contains(WidgetState.selected)) {
      return colorScheme.onSurface;
    }
    return colorScheme.onSurfaceVariant;
  }),
  backgroundColor: WidgetStateProperty.resolveWith((states) {
    if (states.contains(WidgetState.selected)) {
      return colorScheme.primary.withValues(alpha: 0.16);
    }
    return Colors.transparent;
  }),
);
