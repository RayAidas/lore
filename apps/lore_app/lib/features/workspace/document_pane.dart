import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_editor/lore_editor.dart';

import '../preferences/preferences_providers.dart';
import '../library/library_providers.dart';
import 'chapter_title_bar.dart';
import 'library_failure_snackbar.dart';
import 'local_markdown_image.dart';
import 'open_document_extensions.dart';
import 'workspace_controller.dart';

/// 文档编辑/预览主面板：工具条 + 冲突/错误横幅 + 编辑器或预览 + 状态栏。
final class DocumentPane extends ConsumerStatefulWidget {
  const DocumentPane({
    required this.controller,
    required this.document,
    required this.session,
    required this.onReloadConflict,
    super.key,
  });

  final WorkspaceController controller;
  final OpenDocument document;
  final LibrarySession session;
  final VoidCallback onReloadConflict;

  @override
  ConsumerState<DocumentPane> createState() => _DocumentPaneState();
}

final class _DocumentPaneState extends ConsumerState<DocumentPane> {
  /// 章节标题栏按回车后聚焦正文的入口节点；交给 [LoreLargeTextEditor] 转发
  /// 到首个段落块。
  final FocusNode _bodyFocusNode = FocusNode();

  @override
  void dispose() {
    _bodyFocusNode.dispose();
    super.dispose();
  }

  WorkspaceController get controller => widget.controller;
  OpenDocument get document => widget.document;
  LibrarySession get session => widget.session;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: document,
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final prefs =
        ref.watch(appPreferencesProvider).value ?? AppPreferences.defaults();
    final editorStyle = const EditorStyle.defaults().copyWith(
      lineHeight: prefs.editorLineHeight,
      fontSize: prefs.editorFontSize,
      contentWidth: prefs.editorContentWidth,
      typewriterMode: prefs.typewriterMode,
      focusMode: prefs.focusMode,
      firstLineIndent: prefs.firstLineIndent,
      paragraphSpacing: prefs.paragraphSpacing,
    );
    final hasTitle = document.chapterNumber != null;
    return Column(
      children: [
        Container(
          height: 48,
          color: colorScheme.surface,
          child: Row(
            children: [
              const SizedBox(width: 18),
              Icon(
                Icons.folder_open_outlined,
                size: 15,
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
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: const [
                    ButtonSegment(value: false, label: Text('编辑')),
                    ButtonSegment(value: true, label: Text('预览')),
                  ],
                  selected: {document.showPreview},
                  onSelectionChanged: (selection) {
                    controller.setPreview(document, selection.first);
                  },
                ),
              if (!document.isMarkdown) ...[
                IconButton(
                  tooltip: '打字机模式 (Cmd+Shift+T)',
                  isSelected: prefs.typewriterMode,
                  onPressed: () => ref
                      .read(appPreferencesProvider.notifier)
                      .setTypewriterMode(!prefs.typewriterMode),
                  icon: const Icon(Icons.vertical_align_center, size: 18),
                ),
                IconButton(
                  tooltip: '专注模式',
                  isSelected: prefs.focusMode,
                  onPressed: () => ref
                      .read(appPreferencesProvider.notifier)
                      .setFocusMode(!prefs.focusMode),
                  icon: const Icon(Icons.center_focus_strong, size: 18),
                ),
              ],
              const SizedBox(width: 10),
              IconButton(
                tooltip: '保存 (Cmd+S)',
                onPressed: () => unawaited(controller.saveDocument(document)),
                icon: const Icon(Icons.save_outlined, size: 18),
              ),
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
            child: document.showPreview && document.isMarkdown
                ? LoreMarkdownPreview(
                    data: document.editorController.text,
                    imageBuilder: (uri, width, height) => LocalMarkdownImage(
                      session: session,
                      assetService: ref.watch(libraryAssetServiceProvider),
                      documentPath: document.relativePath,
                      uri: uri,
                      width: width,
                      height: height,
                    ),
                  )
                : Column(
                    children: [
                      if (hasTitle)
                        ChapterTitleBar(
                          key: ValueKey('title-${document.relativePath}'),
                          chapterNumber: document.chapterNumber!,
                          subtitle: document.chapterTitleSubtitle,
                          style: editorStyle,
                          autofocusSubtitle:
                              document.editorController.text.isEmpty,
                          onChanged: (value) => controller
                              .updateChapterTitleSubtitle(document, value),
                          onEnter: () {
                            document.editorController.selection =
                                const TextSelection.collapsed(offset: 0);
                            _bodyFocusNode.requestFocus();
                          },
                        ),
                      Expanded(
                        child: switch (document.editorController) {
                          LoreLargeTextController largeController =>
                            LoreLargeTextEditor(
                              key: ValueKey(document.relativePath),
                              controller: largeController,
                              scrollController: document.scrollController,
                              style: editorStyle,
                              // 有标题栏时去掉正文顶部留白，间距由标题栏底 padding 控制。
                              topPadding: hasTitle ? 0 : 42,
                              focusNode: hasTitle ? _bodyFocusNode : null,
                              // 章节正文首段自动补两字缩进（受 firstLineIndent 偏好控制）。
                              indentFirstParagraph: hasTitle,
                              autofocus:
                                  !hasTitle ||
                                  document.editorController.text.isNotEmpty,
                            ),
                          LoreTextController textController => LoreTextEditor(
                            key: ValueKey(document.relativePath),
                            controller: textController,
                            scrollController: document.scrollController,
                            style: editorStyle,
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
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            border: Border(
              top: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            children: [
              Text(
                '本文 ${document.characterCount} 字',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
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
