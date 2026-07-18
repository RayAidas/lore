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
import '../preferences/preferences_providers.dart';
import '../preferences/settings_page.dart';
import 'novel_overview_pane.dart';
import 'trash_pane.dart';
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
  bool _showInspector = true;
  FindReplaceController? _findController;
  bool _findReplaceMode = false;

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
    _findController?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(workspaceControllerProvider(widget.session));
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final permanentSidebar = constraints.maxWidth >= 760;
            final inspectorAvailable = constraints.maxWidth >= 1180;
            final inspectorVisible = inspectorAvailable && _showInspector;
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
                const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () {
                  _openFindReplace(controller, replace: false);
                },
                const SingleActivator(LogicalKeyboardKey.keyH, meta: true): () {
                  _openFindReplace(controller, replace: true);
                },
                const SingleActivator(LogicalKeyboardKey.keyG, meta: true): () {
                  _findController?.next();
                },
                const SingleActivator(
                  LogicalKeyboardKey.keyG,
                  meta: true,
                  shift: true,
                ): () {
                  _findController?.previous();
                },
              },
              child: Focus(
                autofocus: true,
                child: Scaffold(
                  drawer: permanentSidebar
                      ? null
                      : Drawer(
                          child: Builder(
                            builder: (drawerContext) => _buildSidebar(
                              controller,
                              drawerContext: drawerContext,
                            ),
                          ),
                        ),
                  appBar: AppBar(
                    toolbarHeight: 52,
                    titleSpacing: permanentSidebar ? 20 : 0,
                    title: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_stories_outlined,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        const Text('Lore'),
                      ],
                    ),
                    actions: [
                      if (inspectorAvailable)
                        IconButton(
                          onPressed: () =>
                              setState(() => _showInspector = !_showInspector),
                          tooltip: inspectorVisible ? '收起工具栏' : '展开工具栏',
                          icon: Icon(
                            inspectorVisible
                                ? Icons.view_sidebar
                                : Icons.view_sidebar_outlined,
                          ),
                        ),
                      IconButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (context) =>
                                TrashPage(controller: controller),
                          ),
                        ),
                        tooltip: '回收站',
                        icon: const Icon(Icons.delete_outline),
                      ),
                      IconButton(
                        onPressed: () => _openSettings(context),
                        tooltip: '设置',
                        icon: const Icon(Icons.settings_outlined),
                      ),
                      IconButton(
                        onPressed: () => unawaited(_selectLibrary(controller)),
                        tooltip: '重新选择书库',
                        icon: const Icon(Icons.drive_folder_upload_outlined),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                  body: Column(
                    children: [
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
                            if (permanentSidebar)
                              SizedBox(
                                width: 276,
                                child: _buildSidebar(controller),
                              ),
                            if (permanentSidebar)
                              const VerticalDivider(width: 1),
                            Expanded(child: _buildContent(controller)),
                            if (inspectorVisible)
                              const VerticalDivider(width: 1),
                            if (inspectorVisible)
                              SizedBox(
                                width: 320,
                                child: _WorkspaceInspector(
                                  controller: controller,
                                ),
                              ),
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
      },
    );
  }

  Widget _buildSidebar(
    WorkspaceController controller, {
    BuildContext? drawerContext,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerLowest,
      child: SafeArea(
        top: drawerContext != null,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '书库',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  PopupMenuButton<_CreateEntryAction>(
                    tooltip: '新建',
                    icon: const Icon(Icons.add, size: 20),
                    onSelected: (action) {
                      switch (action) {
                        case _CreateEntryAction.novel:
                          unawaited(_createNovel(controller));
                        case _CreateEntryAction.directory:
                          unawaited(_createDirectory(controller));
                        case _CreateEntryAction.text:
                          unawaited(
                            _createDocument(controller, DocumentFormat.text),
                          );
                        case _CreateEntryAction.markdown:
                          unawaited(
                            _createDocument(
                              controller,
                              DocumentFormat.markdown,
                            ),
                          );
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: _CreateEntryAction.novel,
                        child: _MenuItem(
                          icon: Icons.auto_stories_outlined,
                          label: '新建小说',
                        ),
                      ),
                      PopupMenuItem(
                        value: _CreateEntryAction.directory,
                        child: _MenuItem(
                          icon: Icons.create_new_folder_outlined,
                          label: '新建文件夹',
                        ),
                      ),
                      PopupMenuItem(
                        value: _CreateEntryAction.text,
                        child: _MenuItem(
                          icon: Icons.notes_outlined,
                          label: '新建 TXT',
                        ),
                      ),
                      PopupMenuItem(
                        value: _CreateEntryAction.markdown,
                        child: _MenuItem(
                          icon: Icons.description_outlined,
                          label: '新建 Markdown',
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: '重命名',
                    onPressed: controller.selectedEntry == null
                        ? null
                        : () => unawaited(_renameSelected(controller)),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: '删除',
                    onPressed: controller.selectedEntry == null
                        ? null
                        : () => unawaited(_deleteSelected(controller)),
                    icon: const Icon(Icons.delete_outline, size: 18),
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
                          if (drawerContext != null) {
                            Navigator.of(drawerContext).pop();
                          }
                        }
                      },
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_open_outlined,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Tooltip(
                      message: widget.session.access.displayPath,
                      child: Text(
                        widget.session.access.displayPath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: '重新选择书库',
                    onPressed: () => unawaited(_selectLibrary(controller)),
                    icon: const Icon(Icons.settings_outlined, size: 18),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
              : ColoredBox(
                  color: Theme.of(context).colorScheme.surface,
                  child: Center(
                    child: _EmptyWorkspace(
                      hasSelection: controller.selectedPath != null,
                      selectedPath: controller.selectedPath,
                    ),
                  ),
                ),
        ),
        if (_findController != null && activeDocument != null)
          FindReplaceOverlay(
            findController: _findController!,
            editorController: activeDocument.editorController,
            initialShowReplace: _findReplaceMode,
            onClose: _closeFindReplace,
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
    final prefs =
        ref.read(appPreferencesProvider).value ?? AppPreferences.defaults();
    try {
      await controller.createNovel(
        title,
        chapterFormat: prefs.defaultChapterFormat,
      );
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

  Future<void> _deleteSelected(WorkspaceController controller) async {
    final entry = controller.selectedEntry;
    if (entry == null) {
      return;
    }
    final isSemantic = entry.semanticKind != null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除？'),
        content: Text(
          isSemantic ? '卷与章节请在小说结构面板中删除。' : '“${entry.name}”将移到回收站，可在回收站恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: isSemantic
                ? null
                : () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await controller.deleteSelectedEntry();
      } on LibraryOperationException catch (error) {
        _showFailure(error.failure);
      }
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

  void _openSettings(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (context) => const SettingsPage()));
  }

  void _openFindReplace(
    WorkspaceController controller, {
    required bool replace,
  }) {
    final document = controller.activeDocument;
    if (document == null) {
      return;
    }
    final prefs =
        ref.read(appPreferencesProvider).value ?? AppPreferences.defaults();
    setState(() {
      _findReplaceMode = replace;
      _findController = FindReplaceController()
        ..setCaseSensitive(prefs.findMatchCase)
        ..setUseRegex(prefs.findUseRegex)
        ..recompute(document.editorController.text);
    });
  }

  void _closeFindReplace() {
    setState(() {
      _findController?.dispose();
      _findController = null;
    });
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

enum _CreateEntryAction { novel, directory, text, markdown }

final class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [Icon(icon, size: 18), const SizedBox(width: 12), Text(label)],
    );
  }
}

final class _EmptyWorkspace extends StatelessWidget {
  const _EmptyWorkspace({required this.hasSelection, this.selectedPath});

  final bool hasSelection;
  final String? selectedPath;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              hasSelection
                  ? Icons.folder_open_outlined
                  : Icons.edit_note_outlined,
              size: 30,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            hasSelection ? '已选择一个书库项目' : '开始你的写作',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            hasSelection ? selectedPath! : '从左侧选择文件，或新建一部小说',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (!hasSelection) ...[
            const SizedBox(height: 8),
            Text(
              '选择或新建文件开始写作',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
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
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 28, 24, 18),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    isVolume
                        ? Icons.folder_copy_outlined
                        : Icons.menu_book_outlined,
                    size: 23,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isVolume ? selectedEntry.name : snapshot.metadata.title,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
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
                IconButton(
                  tooltip: '小说概览',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => Scaffold(
                        appBar: AppBar(title: const Text('小说概览')),
                        body: NovelOverviewPage(
                          controller: controller,
                          novelId: snapshot.metadata.id,
                        ),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.dashboard_outlined),
                ),
                if (!isVolume)
                  FilledButton.tonalIcon(
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => _run(
                      () => controller.createVolume(snapshot.metadata.id),
                    ),
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('新建卷'),
                  ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
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
                ? Center(
                    child: _InspectorEmpty(
                      icon: isVolume
                          ? Icons.article_outlined
                          : Icons.menu_book_outlined,
                      message: isVolume ? '本卷还没有章节' : '正文还没有卷或章节',
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
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
                      return Padding(
                        key: ValueKey(node.id.value),
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: colorScheme.surfaceContainerLowest,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(color: colorScheme.outlineVariant),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            leading: Icon(
                              node.type == ContentNodeType.volume
                                  ? Icons.folder_copy_outlined
                                  : Icons.article_outlined,
                              color: node.type == ContentNodeType.volume
                                  ? colorScheme.secondary
                                  : colorScheme.primary,
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
                                unawaited(
                                  controller.openPath(entry.relativePath),
                                );
                              }
                            },
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
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
                                    icon: const Icon(
                                      Icons.drive_file_move_outline,
                                      size: 19,
                                    ),
                                  ),
                                IconButton(
                                  tooltip: '重命名',
                                  onPressed: () => _rename(context, node),
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                  ),
                                ),
                                IconButton(
                                  tooltip: '删除',
                                  onPressed: () => _deleteNode(context, node),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                  ),
                                ),
                                const Icon(Icons.drag_handle, size: 19),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
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

  Future<void> _deleteNode(BuildContext context, ContentNode node) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除？'),
        content: Text('“${p.basename(node.relativePath)}”将移到回收站，可在回收站恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _run(
        () => controller.deleteContentNode(snapshot.metadata.id, node.id),
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

final class _WorkspaceInspector extends StatelessWidget {
  const _WorkspaceInspector({required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerLowest,
      child: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            const SizedBox(
              height: 60,
              child: TabBar(
                dividerHeight: 0,
                tabs: [
                  Tab(
                    height: 60,
                    icon: Icon(Icons.auto_awesome_outlined),
                    text: '助手',
                  ),
                  Tab(
                    height: 60,
                    icon: Icon(Icons.format_list_bulleted),
                    text: '大纲',
                  ),
                  Tab(height: 60, icon: Icon(Icons.info_outline), text: '信息'),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: TabBarView(
                children: [
                  const _AssistantPanel(),
                  _OutlinePanel(document: controller.activeDocument),
                  _DocumentInfoPanel(document: controller.activeDocument),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _AssistantPanel extends StatelessWidget {
  const _AssistantPanel();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colorScheme.primaryContainer.withValues(alpha: 0.7),
                colorScheme.tertiaryContainer.withValues(alpha: 0.45),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.auto_awesome, color: colorScheme.primary),
              const SizedBox(height: 14),
              Text(
                'AI 写作助手',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                '错别字检查、人物一致性与 Agent 对话将在后续版本启用。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text('计划能力', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        const _PlannedToolTile(
          icon: Icons.spellcheck_outlined,
          title: '校对与润色',
          subtitle: '检查错别字、病句和标点',
        ),
        const _PlannedToolTile(
          icon: Icons.groups_outlined,
          title: '设定一致性',
          subtitle: '结合书库资料检查人物与世界观',
        ),
        const _PlannedToolTile(
          icon: Icons.account_tree_outlined,
          title: 'Agent 工作流',
          subtitle: '读取并操作授权范围内的书库内容',
        ),
      ],
    );
  }
}

final class _PlannedToolTile extends StatelessWidget {
  const _PlannedToolTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 20),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.lock_clock_outlined, size: 16),
    );
  }
}

final class _OutlinePanel extends StatelessWidget {
  const _OutlinePanel({required this.document});

  final OpenDocument? document;

  @override
  Widget build(BuildContext context) {
    final current = document;
    if (current == null) {
      return const _InspectorEmpty(
        icon: Icons.format_list_bulleted,
        message: '打开文档后查看大纲',
      );
    }
    if (!current.isMarkdown) {
      return const _InspectorEmpty(
        icon: Icons.notes_outlined,
        message: 'TXT 文档暂不生成大纲',
      );
    }
    return ListenableBuilder(
      listenable: current,
      builder: (context, _) => _buildOutline(context, current),
    );
  }

  Widget _buildOutline(BuildContext context, OpenDocument current) {
    final headings = <({int level, String title})>[];
    final headingPattern = RegExp(r'^(#{1,6})\s+(.+)$');
    for (final line in current.editorController.text.split('\n')) {
      final match = headingPattern.firstMatch(line.trimRight());
      if (match != null) {
        headings.add((level: match.group(1)!.length, title: match.group(2)!));
      }
    }
    if (headings.isEmpty) {
      return const _InspectorEmpty(
        icon: Icons.tag_outlined,
        message: '使用 Markdown 标题生成文档大纲',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: headings.length,
      itemBuilder: (context, index) {
        final heading = headings[index];
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.only(
            left: 14.0 + (heading.level - 1) * 14,
            right: 14,
          ),
          leading: Icon(
            heading.level == 1 ? Icons.tag : Icons.subdirectory_arrow_right,
            size: 16,
          ),
          title: Text(
            heading.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }
}

final class _DocumentInfoPanel extends StatelessWidget {
  const _DocumentInfoPanel({required this.document});

  final OpenDocument? document;

  @override
  Widget build(BuildContext context) {
    final current = document;
    if (current == null) {
      return const _InspectorEmpty(
        icon: Icons.info_outline,
        message: '打开文档后查看详细信息',
      );
    }
    return ListenableBuilder(
      listenable: current,
      builder: (context, _) => _buildInfo(context, current),
    );
  }

  Widget _buildInfo(BuildContext context, OpenDocument current) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(
          current.name,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          current.relativePath,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 22),
        _InfoRow(label: '格式', value: current.isMarkdown ? 'Markdown' : 'TXT'),
        _InfoRow(label: '字数', value: '${current.characterCount}'),
        _InfoRow(label: '状态', value: _saveStatusText(current)),
        _InfoRow(
          label: '换行符',
          value: current.snapshot.lineEnding.name.toUpperCase(),
        ),
        _InfoRow(
          label: '编码',
          value: current.snapshot.encoding == TextEncoding.utf8Bom
              ? 'UTF-8 BOM'
              : 'UTF-8',
        ),
      ],
    );
  }
}

final class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

final class _InspectorEmpty extends StatelessWidget {
  const _InspectorEmpty({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
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
    final colorScheme = Theme.of(context).colorScheme;
    if (controller.tabs.isEmpty) {
      return ColoredBox(
        color: colorScheme.surfaceContainerLowest,
        child: const SizedBox(height: 46),
      );
    }
    return ColoredBox(
      color: colorScheme.surfaceContainerLowest,
      child: SizedBox(
        height: 46,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: controller.tabs.length,
          itemBuilder: (context, index) {
            final tab = controller.tabs[index];
            return ListenableBuilder(
              listenable: tab,
              builder: (context, _) {
                final active = controller.activePath == tab.relativePath;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Material(
                    color: active ? colorScheme.surface : Colors.transparent,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(8),
                    ),
                    child: InkWell(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(8),
                      ),
                      onTap: () => unawaited(controller.activateTab(tab)),
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 132,
                          maxWidth: 230,
                        ),
                        padding: const EdgeInsets.only(left: 14),
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(8),
                          ),
                          border: Border(
                            top: BorderSide(
                              color: active
                                  ? colorScheme.primary
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              p.extension(tab.name).toLowerCase() == '.md'
                                  ? Icons.description_outlined
                                  : Icons.notes_outlined,
                              size: 16,
                              color: active
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                tab.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      fontWeight: active
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                    ),
                              ),
                            ),
                            if (tab.hasUnsavedChanges)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                child: Icon(
                                  Icons.circle,
                                  size: 7,
                                  color: colorScheme.primary,
                                ),
                              ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: '关闭',
                              onPressed: () => unawaited(onClose(tab)),
                              icon: const Icon(Icons.close, size: 15),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

final class _DocumentPane extends ConsumerWidget {
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
          child: ColoredBox(
            color: colorScheme.surface,
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
                _saveStatusIcon(document),
                size: 14,
                color: _saveStatusColor(context, document),
              ),
              const SizedBox(width: 6),
              Text(
                _saveStatusText(document),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _saveStatusColor(context, document),
                ),
              ),
            ],
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

IconData _saveStatusIcon(OpenDocument document) {
  return switch (document.saveStatus) {
    DocumentSaveStatus.clean => Icons.check_circle_outline,
    DocumentSaveStatus.dirty => Icons.circle_outlined,
    DocumentSaveStatus.saving => Icons.sync,
    DocumentSaveStatus.conflict => Icons.warning_amber_rounded,
    DocumentSaveStatus.error => Icons.error_outline,
  };
}

Color _saveStatusColor(BuildContext context, OpenDocument document) {
  final colorScheme = Theme.of(context).colorScheme;
  return switch (document.saveStatus) {
    DocumentSaveStatus.clean => colorScheme.onSurfaceVariant,
    DocumentSaveStatus.dirty ||
    DocumentSaveStatus.saving => colorScheme.primary,
    DocumentSaveStatus.conflict => colorScheme.tertiary,
    DocumentSaveStatus.error => colorScheme.error,
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
            minVerticalPadding: 0,
            leading: Icon(
              _entryIcon(entry),
              size: 18,
              color: _entryIconColor(context, entry),
            ),
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
            ? ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: children,
              )
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
    final selected = widget.selectedPath == widget.entry.relativePath;
    final colorScheme = Theme.of(context).colorScheme;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Material(
          color: selected
              ? colorScheme.primaryContainer.withValues(alpha: 0.5)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: ExpansionTile(
            dense: true,
            minTileHeight: 38,
            initiallyExpanded: _expanded,
            iconColor: colorScheme.onSurfaceVariant,
            collapsedIconColor: colorScheme.onSurfaceVariant,
            leading: Icon(
              _expanded && widget.entry.semanticKind == null
                  ? Icons.folder_open_outlined
                  : _entryIcon(widget.entry),
              size: 18,
              color: _entryIconColor(context, widget.entry),
            ),
            title: Text(
              widget.entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            tilePadding: const EdgeInsets.symmetric(horizontal: 8),
            childrenPadding: const EdgeInsets.only(left: 12),
            onExpansionChanged: (expanded) {
              setState(() => _expanded = expanded);
              widget.onSelected(widget.entry);
            },
            children: _expanded
                ? [
                    _WorkspaceDirectory(
                      controller: widget.controller,
                      relativePath: widget.entry.relativePath,
                      selectedPath: widget.selectedPath,
                      reloadToken: widget.reloadToken,
                      onSelected: widget.onSelected,
                    ),
                  ]
                : const [],
          ),
        ),
      ),
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

Color _entryIconColor(BuildContext context, LibraryEntry entry) {
  final colorScheme = Theme.of(context).colorScheme;
  return switch (entry.semanticKind) {
    LibraryEntrySemanticKind.novel => colorScheme.primary,
    LibraryEntrySemanticKind.body => colorScheme.tertiary,
    LibraryEntrySemanticKind.volume => colorScheme.secondary,
    LibraryEntrySemanticKind.chapter => colorScheme.primary,
    null => colorScheme.onSurfaceVariant,
  };
}
