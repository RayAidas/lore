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
  LibraryEntry? _selectedEntry;

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
      _selectedEntry = null;
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
                onPressed: _selectedEntry == null
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
                    setState(() => _selectedEntry = entry);
                    controller.selectPath(entry.relativePath);
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
    final activeDocument = controller.activeDocument;
    return Column(
      children: [
        _DocumentTabs(
          controller: controller,
          onClose: (document) => _closeDocument(controller, document),
        ),
        const Divider(height: 1),
        Expanded(
          child: activeDocument != null
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

  String _creationParentPath() {
    final entry = _selectedEntry;
    if (entry == null) {
      return '';
    }
    if (entry.isDirectory) {
      return entry.relativePath;
    }
    final parent = p.dirname(entry.relativePath);
    return parent == '.' ? '' : parent;
  }

  Future<void> _createDirectory(WorkspaceController controller) async {
    final name = await _promptName(title: '新建文件夹', label: '文件夹名称');
    if (name == null) {
      return;
    }
    try {
      final entry = await controller.createDirectory(
        parentPath: _creationParentPath(),
        name: name,
      );
      setState(() => _selectedEntry = entry);
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
      final entry = await controller.createDocument(
        parentPath: _creationParentPath(),
        name: name,
        format: format,
      );
      setState(() => _selectedEntry = entry);
    } on LibraryOperationException catch (error) {
      _showFailure(error.failure);
    }
  }

  Future<void> _renameSelected(WorkspaceController controller) async {
    final entry = _selectedEntry;
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
      final renamed = await controller.renameSelected(name);
      setState(() => _selectedEntry = renamed);
    } on LibraryOperationException catch (error) {
      _showFailure(error.failure);
    }
  }

  Future<String?> _promptName({
    required String title,
    required String label,
    String initialValue = '',
    String? suffix,
  }) async {
    final textController = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: InputDecoration(labelText: label, suffixText: suffix),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(textController.text),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    textController.dispose();
    return result;
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
            leading: Icon(_fileIcon(entry.type), size: 20),
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
        _expanded ? Icons.folder_open_outlined : Icons.folder_outlined,
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

IconData _fileIcon(LibraryEntryType type) {
  return switch (type) {
    LibraryEntryType.directory => Icons.folder_outlined,
    LibraryEntryType.textFile => Icons.notes_outlined,
    LibraryEntryType.markdownFile => Icons.description_outlined,
    LibraryEntryType.otherFile => Icons.insert_drive_file_outlined,
  };
}
