import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_editor/lore_editor.dart';

import '../preferences/preferences_providers.dart';
import '../library/library_providers.dart';
import 'library_failure_snackbar.dart';
import 'local_markdown_image.dart';
import 'open_document_extensions.dart';
import 'workspace_controller.dart';

/// 文档编辑/预览主面板：工具条 + 冲突/错误横幅 + 编辑器或预览 + 状态栏。
final class DocumentPane extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    return ListenableBuilder(
      listenable: document,
      builder: (context, _) => _buildContent(context, ref),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final prefs =
        ref.watch(appPreferencesProvider).value ?? AppPreferences.defaults();
    final editorStyle = const EditorStyle.defaults().copyWith(
      lineHeight: prefs.editorLineHeight,
      fontSize: prefs.editorFontSize,
      contentWidth: prefs.editorContentWidth,
    );
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
                  onPressed: onReloadConflict,
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
                : LoreTextEditor(
                    key: ValueKey(document.relativePath),
                    controller: document.editorController,
                    scrollController: document.scrollController,
                    style: editorStyle,
                    autofocus: true,
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
