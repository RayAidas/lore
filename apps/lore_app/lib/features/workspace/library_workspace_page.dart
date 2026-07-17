import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_editor/lore_editor.dart';
import 'package:path/path.dart' as p;

import '../library/library_providers.dart';
import 'workspace_controller.dart';

final class LibraryWorkspacePage extends ConsumerStatefulWidget {
  const LibraryWorkspacePage({
    required this.session,
    required this.onSelectLibrary,
    super.key,
  });

  final LibrarySession session;
  final VoidCallback onSelectLibrary;

  @override
  ConsumerState<LibraryWorkspacePage> createState() =>
      _LibraryWorkspacePageState();
}

final class _LibraryWorkspacePageState
    extends ConsumerState<LibraryWorkspacePage>
    with WidgetsBindingObserver {
  WorkspaceController get _controller {
    return ref.read(workspaceControllerProvider(widget.session));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future<void>.microtask(_controller.initialize);
  }

  @override
  void didUpdateWidget(covariant LibraryWorkspacePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      Future<void>.microtask(_controller.initialize);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_controller.flushAll());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(workspaceControllerProvider(widget.session));
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
              unawaited(controller.saveActive());
            },
            const SingleActivator(LogicalKeyboardKey.keyW, meta: true): () {
              final document = controller.activeDocument;
              if (document != null) {
                unawaited(_closeDocument(controller, document));
              }
            },
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Lore'),
                actions: [
                  IconButton(
                    onPressed: () => unawaited(_selectLibrary(controller)),
                    tooltip: '重新选择书库',
                    icon: const Icon(Icons.drive_folder_upload_outlined),
                  ),
                ],
              ),
              body: Column(
                children: [
                  _LibraryPathBar(path: widget.session.access.displayPath),
                  if (controller.workspaceFailure case final failure?)
                    MaterialBanner(
                      content: Text(failure.message),
                      actions: [
                        TextButton(
                          onPressed: controller.dismissWorkspaceFailure,
                          child: const Text('知道了'),
                        ),
                      ],
                    ),
                  Expanded(
                    child: Row(
                      children: [
                        SizedBox(width: 300, child: _buildSidebar(controller)),
                        const VerticalDivider(width: 1),
                        Expanded(child: _buildContent(controller)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSidebar(WorkspaceController controller) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '书库',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '新建小说',
                onPressed: () => unawaited(_createNovel(controller)),
                icon: const Icon(Icons.auto_stories_outlined, size: 20),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '新建文件夹',
                onPressed: () => unawaited(_createDirectory(controller)),
                icon: const Icon(Icons.create_new_folder_outlined, size: 20),
              ),
              PopupMenuButton<DocumentFormat>(
                tooltip: '新建文件',
                icon: const Icon(Icons.note_add_outlined, size: 20),
                onSelected: (format) {
                  unawaited(_createDocument(controller, format));
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: DocumentFormat.text,
                    child: Text('新建 TXT'),
                  ),
                  PopupMenuItem(
                    value: DocumentFormat.markdown,
                    child: Text('新建 Markdown'),
                  ),
                ],
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '重命名',
                onPressed: controller.selectedEntry == null
                    ? null
                    : () => unawaited(_renameSelected(controller)),
                icon: const Icon(Icons.drive_file_rename_outline, size: 20),
              ),
            ],
          ),
        ),
        Expanded(
          child: controller.initialized
              ? _WorkspaceDirectory(
                  controller: controller,
                  relativePath: '',
                  selectedPath: controller.selectedPath,
                  reloadToken: controller.treeRevision,
                  onSelected: (entry) {
                    controller.selectEntry(entry);
                    if (!entry.isDirectory &&
                        entry.type != LibraryEntryType.otherFile) {
                      unawaited(_openPath(controller, entry.relativePath));
                    }
                  },
                )
              : const Center(child: CircularProgressIndicator()),
        ),
      ],
    );
  }

  Widget _buildContent(WorkspaceController controller) {
    if (!controller.initialized) {
      return const Center(child: CircularProgressIndicator());
    }
    final selectedEntry = controller.selectedEntry;
    final selectedNovel = controller.selectedNovel;
    final showStructure =
        selectedNovel != null &&
        switch (selectedEntry?.semanticKind) {
          LibraryEntrySemanticKind.novel ||
          LibraryEntrySemanticKind.body ||
          LibraryEntrySemanticKind.volume => true,
          _ => false,
        };
    final activeDocument = controller.activeDocument;
    return Column(
      children: [
        _DocumentTabs(
          controller: controller,
          onClose: (document) => _closeDocument(controller, document),
        ),
        const Divider(height: 1),
        Expanded(
          child: showStructure
              ? _NovelStructurePane(
                  controller: controller,
                  snapshot: selectedNovel,
                  selectedEntry: selectedEntry!,
                  onFailure: _showFailure,
                )
              : activeDocument != null
              ? _DocumentPane(
                  controller: controller,
                  document: activeDocument,
                  libraryRoot: widget.session.access.token,
                  onReloadConflict: () =>
                      _reloadConflict(controller, activeDocument),
                )
              : Center(
                  child: Text(
                    controller.selectedPath == null
                        ? '选择或新建文件开始写作'
                        : '已选择 ${controller.selectedPath}',
                  ),
                ),
        ),
      ],
    );
  }

  String _creationParentPath(WorkspaceController controller) {
    final entry = controller.selectedEntry;
    if (entry == null) {
      return '';
    }
    if (entry.isDirectory) {
      return entry.relativePath;
    }
    final parent = p.dirname(entry.relativePath);
    return parent == '.' ? '' : parent;
  }

  Future<void> _createNovel(WorkspaceController controller) async {
    final title = await _promptName(title: '新建小说', label: '书名');
    if (title == null) {
      return;
    }
    try {
      await controller.createNovel(title);
    } on LibraryOperationException catch (error) {
      if (error.failure.code != LibraryFailureCode.alreadyExists || !mounted) {
        _showFailure(error.failure);
        return;
      }
      final register = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('同名目录已存在'),
          content: Text('是否将“${title.trim()}”注册为小说并扫描其中的正文？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('修改书名'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('注册现有目录'),
            ),
          ],
        ),
      );
      if (register == true) {
        try {
          await controller.registerExistingNovel(title.trim());
        } on LibraryOperationException catch (registerError) {
          _showFailure(registerError.failure);
        }
      }
    }
  }

  Future<void> _createDirectory(WorkspaceController controller) async {
    final name = await _promptName(title: '新建文件夹', label: '文件夹名称');
    if (name == null) {
      return;
    }
    try {
      await controller.createDirectory(
        parentPath: _creationParentPath(controller),
        name: name,
      );
    } on LibraryOperationException catch (error) {
      _showFailure(error.failure);
    }
  }

  Future<void> _createDocument(
    WorkspaceController controller,
    DocumentFormat format,
  ) async {
    final extension = format == DocumentFormat.text ? '.txt' : '.md';
    final name = await _promptName(
      title: format == DocumentFormat.text ? '新建 TXT 文件' : '新建 Markdown 文件',
      label: '文件名称',
      suffix: extension,
    );
    if (name == null) {
      return;
    }
    try {
      await controller.createDocument(
        parentPath: _creationParentPath(controller),
        name: name,
        format: format,
      );
    } on LibraryOperationException catch (error) {
      _showFailure(error.failure);
    }
  }

  Future<void> _renameSelected(WorkspaceController controller) async {
    final entry = controller.selectedEntry;
    if (entry == null) {
      return;
    }
    final isDocument =
        !entry.isDirectory && entry.type != LibraryEntryType.otherFile;
    final initial = isDocument
        ? p.basenameWithoutExtension(entry.name)
        : entry.name;
    final name = await _promptName(
      title: '重命名',
      label: '新名称',
      initialValue: initial,
      suffix: isDocument ? p.extension(entry.name) : null,
    );
    if (name == null) {
      return;
    }
    try {
      final novelId = entry.novelId == null ? null : NovelId(entry.novelId!);
      await switch (entry.semanticKind) {
        LibraryEntrySemanticKind.novel when novelId != null =>
          controller.renameNovel(novelId, name),
        LibraryEntrySemanticKind.body when novelId != null =>
          controller.renameBody(novelId, name),
        LibraryEntrySemanticKind.volume || LibraryEntrySemanticKind.chapter
            when novelId != null && entry.semanticId != null =>
          controller.renameContentNode(
            novelId,
            ContentId(entry.semanticId!),
            name,
          ),
        _ => controller.renameSelected(name),
      };
    } on LibraryOperationException catch (error) {
      _showFailure(error.failure);
    }
  }

  Future<String?> _promptName({
    required String title,
    required String label,
    String initialValue = '',
    String? suffix,
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) => _NamePromptDialog(
        title: title,
        label: label,
        initialValue: initialValue,
        suffix: suffix,
      ),
    );
  }

  Future<void> _closeDocument(
    WorkspaceController controller,
    WorkspaceTab tab,
  ) async {
    if (!await controller.closeTab(tab) && mounted) {
      final document = tab as OpenDocument;
      _showFailure(
        document.failure ??
            const LibraryFailure(
              code: LibraryFailureCode.externalModification,
              message: '文档存在未处理的冲突，暂时无法关闭。',
            ),
      );
    }
  }

  Future<void> _openPath(
    WorkspaceController controller,
    String relativePath,
  ) async {
    try {
      await controller.openPath(relativePath);
    } on LibraryOperationException catch (error) {
      _showFailure(error.failure);
    }
  }

  Future<void> _reloadConflict(
    WorkspaceController controller,
    OpenDocument document,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重新加载磁盘版本？'),
        content: const Text('当前未保存的修改将被放弃。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('重新加载'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.reloadConflict(document);
    }
  }

  Future<void> _selectLibrary(WorkspaceController controller) async {
    if (await controller.flushAll()) {
      widget.onSelectLibrary();
    } else if (mounted) {
      _showFailure(
        const LibraryFailure(
          code: LibraryFailureCode.externalModification,
          message: '请先处理未保存文档或外部修改冲突。',
        ),
      );
    }
  }

  void _showFailure(LibraryFailure failure) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(failure.message)));
  }
}

final class _NamePromptDialog extends StatefulWidget {
  const _NamePromptDialog({
    required this.title,
    required this.label,
    required this.initialValue,
    this.suffix,
  });

  final String title;
  final String label;
  final String initialValue;
  final String? suffix;

  @override
  State<_NamePromptDialog> createState() => _NamePromptDialogState();
}

final class _NamePromptDialogState extends State<_NamePromptDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: widget.label,
          suffixText: widget.suffix,
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('确认'),
        ),
      ],
    );
  }
}

final class _NovelStructurePane extends StatelessWidget {
  const _NovelStructurePane({
    required this.controller,
    required this.snapshot,
    required this.selectedEntry,
    required this.onFailure,
  });

  final WorkspaceController controller;
  final NovelSnapshot snapshot;
  final LibraryEntry selectedEntry;
  final ValueChanged<LibraryFailure> onFailure;

  ContentId get _parentId {
    if (selectedEntry.semanticKind == LibraryEntrySemanticKind.volume) {
      return ContentId(selectedEntry.semanticId!);
    }
    return snapshot.metadata.body.id;
  }

  @override
  Widget build(BuildContext context) {
    final nodes = snapshot.contentTree.childrenOf(_parentId);
    final isVolume =
        selectedEntry.semanticKind == LibraryEntrySemanticKind.volume;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
          child: Row(
            children: [
              Icon(
                isVolume
                    ? Icons.folder_copy_outlined
                    : Icons.menu_book_outlined,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isVolume ? selectedEntry.name : snapshot.metadata.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      isVolume
                          ? '${nodes.length} 章'
                          : '${snapshot.contentTree.nodes.where((node) => node.type == ContentNodeType.volume).length} 卷 · ${snapshot.contentTree.nodes.where((node) => node.type == ContentNodeType.chapter).length} 章',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (!isVolume)
                FilledButton.tonalIcon(
                  onPressed: () =>
                      _run(() => controller.createVolume(snapshot.metadata.id)),
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('新建卷'),
                ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _run(
                  () => controller.createChapter(
                    snapshot.metadata.id,
                    volumeId: isVolume ? _parentId : null,
                  ),
                ),
                icon: const Icon(Icons.note_add_outlined),
                label: const Text('新建章'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (controller.reconciliationIssues.isNotEmpty)
          MaterialBanner(
            content: Text(controller.reconciliationIssues.first.message),
            actions: const [SizedBox.shrink()],
          ),
        Expanded(
          child: nodes.isEmpty
              ? Center(child: Text(isVolume ? '本卷还没有章节' : '正文还没有卷或章节'))
              : ReorderableListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: nodes.length,
                  onReorderItem: (oldIndex, newIndex) {
                    _run(
                      () => controller.reorderContentNode(
                        snapshot.metadata.id,
                        nodes[oldIndex].id,
                        newIndex,
                      ),
                    );
                  },
                  itemBuilder: (context, index) {
                    final node = nodes[index];
                    return ListTile(
                      key: ValueKey(node.id.value),
                      leading: Icon(
                        node.type == ContentNodeType.volume
                            ? Icons.folder_copy_outlined
                            : Icons.article_outlined,
                      ),
                      title: Text(p.basename(node.relativePath)),
                      subtitle: Text(
                        node.type == ContentNodeType.volume
                            ? '${snapshot.contentTree.childrenOf(node.id).length} 章'
                            : node.number == null
                            ? '未编号章节'
                            : '第 ${node.number} 章',
                      ),
                      onTap: () {
                        final entry = _entryForNode(node);
                        controller.selectEntry(entry);
                        if (node.type == ContentNodeType.chapter) {
                          unawaited(controller.openPath(entry.relativePath));
                        }
                      },
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '上移',
                            onPressed: index == 0
                                ? null
                                : () => _run(
                                    () => controller.reorderContentNode(
                                      snapshot.metadata.id,
                                      node.id,
                                      index - 1,
                                    ),
                                  ),
                            icon: const Icon(Icons.keyboard_arrow_up),
                          ),
                          IconButton(
                            tooltip: '下移',
                            onPressed: index == nodes.length - 1
                                ? null
                                : () => _run(
                                    () => controller.reorderContentNode(
                                      snapshot.metadata.id,
                                      node.id,
                                      index + 1,
                                    ),
                                  ),
                            icon: const Icon(Icons.keyboard_arrow_down),
                          ),
                          if (node.type == ContentNodeType.chapter)
                            PopupMenuButton<String>(
                              tooltip: '移动章节',
                              onSelected: (target) => _run(
                                () => controller.moveChapter(
                                  snapshot.metadata.id,
                                  node.id,
                                  volumeId: target == 'body'
                                      ? null
                                      : ContentId(target),
                                ),
                              ),
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'body',
                                  child: Text('移动到正文根级'),
                                ),
                                ...snapshot.contentTree.nodes
                                    .where(
                                      (candidate) =>
                                          candidate.type ==
                                          ContentNodeType.volume,
                                    )
                                    .map(
                                      (volume) => PopupMenuItem(
                                        value: volume.id.value,
                                        child: Text(
                                          '移动到 ${p.basename(volume.relativePath)}',
                                        ),
                                      ),
                                    ),
                              ],
                              icon: const Icon(Icons.drive_file_move_outline),
                            ),
                          IconButton(
                            tooltip: '重命名',
                            onPressed: () => _rename(context, node),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          const Icon(Icons.drag_handle),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  LibraryEntry _entryForNode(ContentNode node) {
    final relativePath = p.join(snapshot.rootPath, node.relativePath);
    return LibraryEntry(
      name: p.basename(node.relativePath),
      relativePath: relativePath,
      type: node.type == ContentNodeType.volume
          ? LibraryEntryType.directory
          : p.extension(node.relativePath).toLowerCase() == '.txt'
          ? LibraryEntryType.textFile
          : LibraryEntryType.markdownFile,
      semanticKind: node.type == ContentNodeType.volume
          ? LibraryEntrySemanticKind.volume
          : LibraryEntrySemanticKind.chapter,
      semanticId: node.id.value,
      novelId: snapshot.metadata.id.value,
      semanticOrder: node.order,
    );
  }

  Future<void> _rename(BuildContext context, ContentNode node) async {
    final extension = node.type == ContentNodeType.chapter
        ? p.extension(node.relativePath)
        : null;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _NamePromptDialog(
        title: node.type == ContentNodeType.volume ? '重命名卷' : '重命名章节',
        label: '新名称',
        initialValue: extension == null
            ? p.basename(node.relativePath)
            : p.basenameWithoutExtension(node.relativePath),
        suffix: extension,
      ),
    );
    if (name != null) {
      await _run(
        () => controller.renameContentNode(snapshot.metadata.id, node.id, name),
      );
    }
  }

  Future<void> _run(Future<Object?> Function() operation) async {
    try {
      await operation();
    } on LibraryOperationException catch (error) {
      onFailure(error.failure);
    }
  }
}

final class _LibraryPathBar extends StatelessWidget {
  const _LibraryPathBar({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Text(
        path,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

final class _DocumentTabs extends StatelessWidget {
  const _DocumentTabs({required this.controller, required this.onClose});

  final WorkspaceController controller;
  final Future<void> Function(WorkspaceTab tab) onClose;

  @override
  Widget build(BuildContext context) {
    if (controller.tabs.isEmpty) {
      return const SizedBox(height: 42);
    }
    return SizedBox(
      height: 42,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: controller.tabs.length,
        itemBuilder: (context, index) {
          final tab = controller.tabs[index];
          return ListenableBuilder(
            listenable: tab,
            builder: (context, _) {
              final active = controller.activePath == tab.relativePath;
              return InkWell(
                onTap: () => unawaited(controller.activateTab(tab)),
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 120,
                    maxWidth: 220,
                  ),
                  padding: const EdgeInsets.only(left: 12),
                  decoration: BoxDecoration(
                    color: active
                        ? Theme.of(context).colorScheme.surface
                        : Theme.of(context).colorScheme.surfaceContainerLow,
                    border: Border(
                      right: BorderSide(color: Theme.of(context).dividerColor),
                      bottom: BorderSide(
                        color: active
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (tab.hasUnsavedChanges)
                        const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Icon(Icons.circle, size: 7),
                        ),
                      Expanded(
                        child: Text(
                          tab.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: '关闭',
                        onPressed: () => unawaited(onClose(tab)),
                        icon: const Icon(Icons.close, size: 16),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

final class _DocumentPane extends StatelessWidget {
  const _DocumentPane({
    required this.controller,
    required this.document,
    required this.libraryRoot,
    required this.onReloadConflict,
  });

  final WorkspaceController controller;
  final OpenDocument document;
  final String libraryRoot;
  final VoidCallback onReloadConflict;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: document,
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 44,
          child: Row(
            children: [
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  document.relativePath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (document.isMarkdown)
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, label: Text('编辑')),
                    ButtonSegment(value: true, label: Text('预览')),
                  ],
                  selected: {document.showPreview},
                  onSelectionChanged: (selection) {
                    controller.setPreview(document, selection.first);
                  },
                ),
              const SizedBox(width: 8),
              Text(_saveStatusText(document)),
              IconButton(
                tooltip: '保存 (Cmd+S)',
                onPressed: () => unawaited(controller.saveDocument(document)),
                icon: const Icon(Icons.save_outlined, size: 20),
              ),
              const SizedBox(width: 8),
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(error.failure.message)),
                      );
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
          child: document.showPreview && document.isMarkdown
              ? LoreMarkdownPreview(
                  data: document.editorController.text,
                  imageBuilder: (uri, width, height) => _LocalMarkdownImage(
                    libraryRoot: libraryRoot,
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
                  autofocus: true,
                ),
        ),
      ],
    );
  }
}

final class _LocalMarkdownImage extends StatelessWidget {
  const _LocalMarkdownImage({
    required this.libraryRoot,
    required this.documentPath,
    required this.uri,
    required this.width,
    required this.height,
  });

  final String libraryRoot;
  final String documentPath;
  final Uri uri;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    if (uri.hasScheme || uri.path.isEmpty || p.isAbsolute(uri.path)) {
      return _placeholder();
    }
    return FutureBuilder<String?>(
      future: _resolvePath(),
      builder: (context, snapshot) {
        final path = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done || path == null) {
          return _placeholder();
        }
        return Image.file(
          File(path),
          width: width,
          height: height,
          errorBuilder: (context, error, stackTrace) => _placeholder(),
        );
      },
    );
  }

  Future<String?> _resolvePath() async {
    try {
      final root = p.normalize(
        await Directory(libraryRoot).resolveSymbolicLinks(),
      );
      final candidate = p.normalize(
        p.join(root, p.dirname(documentPath), uri.path),
      );
      if (!p.isWithin(root, candidate)) {
        return null;
      }
      final type = await FileSystemEntity.type(candidate, followLinks: false);
      if (type != FileSystemEntityType.file) {
        return null;
      }
      final resolved = p.normalize(
        await File(candidate).resolveSymbolicLinks(),
      );
      return p.isWithin(root, resolved) ? resolved : null;
    } on FileSystemException {
      return null;
    }
  }

  Widget _placeholder() {
    return Tooltip(
      message: uri.toString(),
      child: const Icon(Icons.image_not_supported_outlined),
    );
  }
}

String _saveStatusText(OpenDocument document) {
  return switch (document.saveStatus) {
    DocumentSaveStatus.clean => '已保存',
    DocumentSaveStatus.dirty => '未保存',
    DocumentSaveStatus.saving => '保存中…',
    DocumentSaveStatus.conflict => '存在冲突',
    DocumentSaveStatus.error => '保存失败',
  };
}

final class _WorkspaceDirectory extends StatefulWidget {
  const _WorkspaceDirectory({
    required this.controller,
    required this.relativePath,
    required this.selectedPath,
    required this.reloadToken,
    required this.onSelected,
  });

  final WorkspaceController controller;
  final String relativePath;
  final String? selectedPath;
  final int reloadToken;
  final ValueChanged<LibraryEntry> onSelected;

  @override
  State<_WorkspaceDirectory> createState() => _WorkspaceDirectoryState();
}

final class _WorkspaceDirectoryState extends State<_WorkspaceDirectory> {
  late Future<List<LibraryEntry>> _entries;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant _WorkspaceDirectory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.relativePath != widget.relativePath ||
        oldWidget.reloadToken != widget.reloadToken) {
      _reload();
    }
  }

  void _reload() {
    _entries = widget.controller.listChildren(
      relativePath: widget.relativePath,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LibraryEntry>>(
      future: _entries,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return widget.relativePath.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : const LinearProgressIndicator();
        }
        if (snapshot.hasError) {
          return TextButton(
            onPressed: () => setState(_reload),
            child: const Text('目录加载失败，点击重试'),
          );
        }
        final entries = snapshot.data ?? const <LibraryEntry>[];
        if (entries.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(widget.relativePath.isEmpty ? '书库为空' : '文件夹为空'),
          );
        }
        final children = entries.map((entry) {
          if (entry.isDirectory) {
            return _WorkspaceDirectoryTile(
              entry: entry,
              controller: widget.controller,
              selectedPath: widget.selectedPath,
              reloadToken: widget.reloadToken,
              onSelected: widget.onSelected,
            );
          }
          return ListTile(
            dense: true,
            leading: Icon(_entryIcon(entry), size: 20),
            title: Text(
              entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            selected: widget.selectedPath == entry.relativePath,
            onTap: () => widget.onSelected(entry),
          );
        }).toList();
        return widget.relativePath.isEmpty
            ? ListView(children: children)
            : Column(mainAxisSize: MainAxisSize.min, children: children);
      },
    );
  }
}

final class _WorkspaceDirectoryTile extends StatefulWidget {
  const _WorkspaceDirectoryTile({
    required this.entry,
    required this.controller,
    required this.selectedPath,
    required this.reloadToken,
    required this.onSelected,
  });

  final LibraryEntry entry;
  final WorkspaceController controller;
  final String? selectedPath;
  final int reloadToken;
  final ValueChanged<LibraryEntry> onSelected;

  @override
  State<_WorkspaceDirectoryTile> createState() =>
      _WorkspaceDirectoryTileState();
}

final class _WorkspaceDirectoryTileState
    extends State<_WorkspaceDirectoryTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      dense: true,
      initiallyExpanded: _expanded,
      leading: Icon(
        _expanded && widget.entry.semanticKind == null
            ? Icons.folder_open_outlined
            : _entryIcon(widget.entry),
        size: 20,
      ),
      title: Text(
        widget.entry.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: const EdgeInsets.only(left: 16),
      onExpansionChanged: (expanded) {
        setState(() => _expanded = expanded);
        widget.onSelected(widget.entry);
      },
      children: _expanded
          ? [
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: _WorkspaceDirectory(
                  controller: widget.controller,
                  relativePath: widget.entry.relativePath,
                  selectedPath: widget.selectedPath,
                  reloadToken: widget.reloadToken,
                  onSelected: widget.onSelected,
                ),
              ),
            ]
          : const [],
    );
  }
}

IconData _entryIcon(LibraryEntry entry) {
  final semanticIcon = switch (entry.semanticKind) {
    LibraryEntrySemanticKind.novel => Icons.auto_stories_outlined,
    LibraryEntrySemanticKind.body => Icons.menu_book_outlined,
    LibraryEntrySemanticKind.volume => Icons.folder_copy_outlined,
    LibraryEntrySemanticKind.chapter => Icons.article_outlined,
    null => null,
  };
  if (semanticIcon != null) {
    return semanticIcon;
  }
  return switch (entry.type) {
    LibraryEntryType.directory => Icons.folder_outlined,
    LibraryEntryType.textFile => Icons.notes_outlined,
    LibraryEntryType.markdownFile => Icons.description_outlined,
    LibraryEntryType.otherFile => Icons.insert_drive_file_outlined,
  };
}
