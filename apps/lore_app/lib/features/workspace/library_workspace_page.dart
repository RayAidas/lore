import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_editor/lore_editor.dart';
import 'package:lore_ui/lore_ui.dart';

import '../library/library_providers.dart';
import '../preferences/preferences_providers.dart';
import '../preferences/settings_page.dart';
import 'document_pane.dart';
import 'document_tabs.dart';
import 'empty_workspace.dart';
import 'library_failure_snackbar.dart';
import 'library_sidebar.dart';
import 'novel_structure_pane.dart';
import 'trash_pane.dart';
import 'workspace_controller.dart';
import 'workspace_entry_actions.dart';
import 'workspace_inspector.dart';

/// 写作工作区主页：侧栏 + 内容区 + 工具栏三栏布局，按宽度自适应。
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
    if (state == AppLifecycleState.resumed) {
      unawaited(_controller.reconcileAfterForeground());
      return;
    }
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
                const SingleActivator(
                  LogicalKeyboardKey.keyT,
                  meta: true,
                  shift: true,
                ): () {
                  final current =
                      ref.read(appPreferencesProvider).value ??
                      AppPreferences.defaults();
                  ref
                      .read(appPreferencesProvider.notifier)
                      .setTypewriterMode(!current.typewriterMode);
                },
              },
              child: Focus(
                autofocus: true,
                child: Scaffold(
                  drawer: permanentSidebar
                      ? null
                      : Drawer(
                          child: Builder(
                            builder: (drawerContext) => LibrarySidebar(
                              controller: controller,
                              displayPath: widget.session.access.displayPath,
                              onSelectLibrary: widget.onSelectLibrary,
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
                                child: LibrarySidebar(
                                  controller: controller,
                                  displayPath:
                                      widget.session.access.displayPath,
                                  onSelectLibrary: widget.onSelectLibrary,
                                ),
                              ),
                            if (permanentSidebar)
                              const VerticalDivider(width: 1),
                            Expanded(child: _buildContent(controller)),
                            if (inspectorVisible)
                              const VerticalDivider(width: 1),
                            if (inspectorVisible)
                              SizedBox(
                                width: 320,
                                child: WorkspaceInspector(
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
        DocumentTabs(
          controller: controller,
          onClose: (document) => _closeDocument(controller, document),
          onContextMenu: (tab, offset) =>
              _showTabContextMenu(controller, tab, offset),
        ),
        const Divider(height: 1),
        Expanded(
          child: showStructure
              ? NovelStructurePane(
                  controller: controller,
                  snapshot: selectedNovel,
                  selectedEntry: selectedEntry!,
                  onFailure: _showFailure,
                )
              : activeDocument != null
              ? DocumentPane(
                  controller: controller,
                  document: activeDocument,
                  session: widget.session,
                  onReloadConflict: () =>
                      _reloadConflict(controller, activeDocument),
                )
              : ColoredBox(
                  color: Theme.of(context).colorScheme.surface,
                  child: Center(
                    child: EmptyWorkspace(
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

  /// 右键/长按标签时弹出上下文菜单：标签管理（关闭类）+ 文件操作（重命名/
  /// 复制路径/Finder/移到回收站）。右键不激活标签——动作直接作用于被右键的 tab。
  void _showTabContextMenu(
    WorkspaceController controller,
    WorkspaceTab tab,
    Offset position,
  ) {
    showLoreContextMenu(
      context: context,
      position: position,
      items: _buildTabContextMenuItems(controller, tab),
    );
  }

  List<LoreContextMenuItem> _buildTabContextMenuItems(
    WorkspaceController controller,
    WorkspaceTab tab,
  ) {
    return <LoreContextMenuItem>[
      LoreContextMenuItem(
        label: '关闭',
        onTap: () => unawaited(_closeDocument(controller, tab)),
      ),
      LoreContextMenuItem(
        label: '关闭其他',
        onTap: () => unawaited(_closeBatch(() => controller.closeOthers(tab))),
      ),
      LoreContextMenuItem(
        label: '关闭右侧',
        onTap: () => unawaited(
          _closeBatch(() => controller.closeTabsToRight(tab)),
        ),
      ),
      LoreContextMenuItem(
        label: '关闭全部',
        onTap: () => unawaited(_closeBatch(controller.closeAllTabs)),
      ),
      LoreContextMenuItem(
        label: '重命名',
        onTap: () => unawaited(
          renameDocumentFlow(
            context: context,
            controller: controller,
            relativePath: tab.relativePath,
            displayName: tab.name,
          ),
        ),
      ),
      LoreContextMenuItem(
        label: '复制路径',
        onTap: () => unawaited(_copyTabPath(tab)),
      ),
      if (controller.revealGateway != null)
        LoreContextMenuItem(
          label: '在 Finder 中显示',
          onTap: () => unawaited(controller.revealEntry(tab.relativePath)),
        ),
      LoreContextMenuItem(
        label: '移到回收站',
        destructive: true,
        onTap: () => unawaited(
          deleteDocumentFlow(
            context: context,
            controller: controller,
            relativePath: tab.relativePath,
            displayName: tab.name,
          ),
        ),
      ),
    ];
  }

  Future<void> _copyTabPath(WorkspaceTab tab) async {
    await Clipboard.setData(ClipboardData(text: tab.relativePath));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制路径'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// 执行批量关闭；若存在因冲突无法关闭的标签，提示用户先处理。
  Future<void> _closeBatch(
    Future<List<WorkspaceTab>> Function() action,
  ) async {
    final stuck = await action();
    if (!mounted || stuck.isEmpty) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${stuck.length} 个标签因冲突未关闭，请先处理'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _reloadConflict(
    WorkspaceController controller,
    OpenDocument document,
  ) async {
    final confirmed = await showLoreConfirmDialog(
      context: context,
      title: '重新加载磁盘版本？',
      message: '当前未保存的修改将被放弃。',
      confirmLabel: '重新加载',
      destructive: true,
    );
    if (confirmed) {
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
    showLibraryFailure(context, failure);
  }
}
