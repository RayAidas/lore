import 'dart:async';

import 'package:flutter/foundation.dart';
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
  bool _showSidebar = true;

  /// 页面级全屏（沉浸写作）：隐藏 AppBar/侧栏/工具栏/标签页。[DocumentPane]
  /// 始终留在 [_buildEditorGroup] 原位（chrome 折叠为零尺寸占位而非移除），
  /// 编辑器不重挂载，滚动/焦点/选区保留。瞬时视图状态，不落盘。
  bool _isFullscreen = false;

  final ValueNotifier<double> _sidebarWidth = ValueNotifier(
    _defaultSidebarWidth,
  );
  FindReplaceController? _findController;
  bool _findReplaceMode = false;
  WorkspaceTabDragData? _draggingTab;

  WorkspaceController get _controller {
    return ref.read(workspaceControllerProvider(widget.session));
  }

  bool get _supportsSplit => switch (defaultTargetPlatform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => true,
    _ => false,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future<void>.microtask(_initializeController);
  }

  @override
  void didUpdateWidget(covariant LibraryWorkspacePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      // 切换书库回到普通三栏布局：全屏是瞬时视图状态，不应跨书库延续。
      _isFullscreen = false;
      Future<void>.microtask(_initializeController);
    }
  }

  Future<void> _initializeController() async {
    await _controller.initialize();
    if (!_supportsSplit && _controller.isSplit) {
      _controller.closeSplit();
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
    _sidebarWidth.dispose();
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
            final inspectorVisible =
                inspectorAvailable && _showInspector && !_isFullscreen;
            // 全屏下侧栏折叠为零宽度占位而非移除，使 chrome 显隐不动内容子树位置。
            final showSidebar =
                permanentSidebar && _showSidebar && !_isFullscreen;
            final desktop = _supportsSplit;
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
                if (desktop)
                  const SingleActivator(
                    LogicalKeyboardKey.backslash,
                    meta: true,
                  ): () {
                    final tab = controller.activeDocument;
                    if (tab != null) {
                      if (controller.isSplit) {
                        controller.closeSplit();
                      } else {
                        controller.splitRight(tab);
                      }
                    }
                  },
                if (desktop)
                  const SingleActivator(
                    LogicalKeyboardKey.digit1,
                    meta: true,
                  ): () =>
                      _focusGroup(controller, WorkspaceEditorGroupId.primary),
                if (desktop && controller.isSplit)
                  const SingleActivator(
                    LogicalKeyboardKey.digit2,
                    meta: true,
                  ): () =>
                      _focusGroup(controller, WorkspaceEditorGroupId.secondary),
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
                const SingleActivator(
                  LogicalKeyboardKey.keyF,
                  meta: true,
                  shift: true,
                ): _toggleFullscreen,
                if (_isFullscreen)
                  const SingleActivator(LogicalKeyboardKey.escape):
                      _toggleFullscreen,
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
                  appBar: _isFullscreen
                      ? null
                      : AppBar(
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
                            if (desktop && controller.activeDocument != null)
                              IconButton(
                                onPressed: () {
                                  if (controller.isSplit) {
                                    controller.closeSplit();
                                  } else {
                                    controller.splitRight(
                                      controller.activeDocument!,
                                    );
                                  }
                                },
                                tooltip: controller.isSplit ? '关闭分屏' : '向右分屏',
                                icon: Icon(
                                  controller.isSplit
                                      ? Icons.close_fullscreen
                                      : Icons.vertical_split_outlined,
                                ),
                              ),
                            if (controller.activeDocument != null)
                              IconButton(
                                onPressed: _toggleFullscreen,
                                tooltip: '全屏 (Cmd+Shift+F)',
                                icon: const Icon(Icons.fullscreen),
                              ),
                            if (inspectorAvailable)
                              IconButton(
                                onPressed: () => setState(
                                  () => _showInspector = !_showInspector,
                                ),
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
                              onPressed: () =>
                                  unawaited(_selectLibrary(controller)),
                              tooltip: '重新选择书库',
                              icon: const Icon(
                                Icons.drive_folder_upload_outlined,
                              ),
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
                        key: const ValueKey('workspace-editor-row'),
                        child: Row(
                          // 固定 5 槽 + 内容稳定 key：chrome 显隐不重挂载内容子树。
                          children: [
                            showSidebar
                                ? ValueListenableBuilder<double>(
                                    valueListenable: _sidebarWidth,
                                    child: LibrarySidebar(
                                      controller: controller,
                                      displayPath:
                                          widget.session.access.displayPath,
                                      onSelectLibrary: widget.onSelectLibrary,
                                      onCollapse: () =>
                                          setState(() => _showSidebar = false),
                                    ),
                                    builder: (context, width, child) =>
                                        SizedBox(
                                          key: const ValueKey(
                                            'library-sidebar',
                                          ),
                                          width: width,
                                          child: child,
                                        ),
                                  )
                                : const SizedBox.shrink(),
                            showSidebar
                                ? GestureDetector(
                                    key: const ValueKey(
                                      'library-sidebar-resize-handle',
                                    ),
                                    behavior: HitTestBehavior.opaque,
                                    onHorizontalDragUpdate: (details) {
                                      _sidebarWidth.value =
                                          (_sidebarWidth.value +
                                                  details.delta.dx)
                                              .clamp(
                                                _minimumSidebarWidth,
                                                _maximumSidebarWidth,
                                              );
                                    },
                                    child: MouseRegion(
                                      cursor: SystemMouseCursors.resizeColumn,
                                      child: SizedBox(
                                        width: _sidebarResizeHandleWidth,
                                        child: Center(
                                          child: VerticalDivider(
                                            width: 1,
                                            color: Theme.of(
                                              context,
                                            ).dividerColor,
                                          ),
                                        ),
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                            Expanded(
                              // 稳定 key：chrome 显隐时按位匹配可能错配，按键匹配保内容子树不重挂载。
                              key: const ValueKey('workspace-editor-content'),
                              child: _buildContent(
                                controller,
                                desktop: desktop,
                              ),
                            ),
                            inspectorVisible
                                ? const VerticalDivider(width: 1)
                                : const SizedBox.shrink(),
                            inspectorVisible
                                ? SizedBox(
                                    width: 320,
                                    child: WorkspaceInspector(
                                      controller: controller,
                                    ),
                                  )
                                : const SizedBox.shrink(),
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

  Widget _buildContent(
    WorkspaceController controller, {
    required bool desktop,
  }) {
    final showSidebarExpander =
        MediaQuery.sizeOf(context).width >= 760 &&
        !_showSidebar &&
        !_isFullscreen;
    if (!controller.initialized) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!desktop) {
      return _buildEditorGroup(
        controller,
        WorkspaceEditorGroupId.primary,
        showSidebarExpander: showSidebarExpander,
        hideTabs: _isFullscreen,
      );
    }
    if (!controller.isSplit) {
      final editorGroup = _buildEditorGroup(
        controller,
        WorkspaceEditorGroupId.primary,
        showSidebarExpander: showSidebarExpander,
        hideTabs: _isFullscreen,
      );
      if (_draggingTab == null) {
        return editorGroup;
      }
      return LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            Positioned.fill(child: editorGroup),
            Positioned(
              top: DocumentTabs.barHeight + 1,
              right: 0,
              bottom: 0,
              width: constraints.maxWidth / 2,
              child: DragTarget<WorkspaceTabDragData>(
                onWillAcceptWithDetails: (_) => true,
                onAcceptWithDetails: (details) {
                  _discardFindReplace();
                  controller.splitRight(details.data.tab);
                  _finishTabDrag();
                },
                builder: (context, candidates, _) {
                  if (candidates.isEmpty) {
                    return const SizedBox.expand();
                  }
                  return Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withAlpha(90),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '在右侧创建分屏',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
    return LayoutBuilder(
      builder: (context, constraints) {
        const minimumPaneWidth = 280.0;
        const dividerWidth = 9.0;
        if (constraints.maxWidth < minimumPaneWidth * 2 + dividerWidth) {
          return _buildEditorGroup(
            controller,
            controller.focusedGroupId,
            showSidebarExpander: showSidebarExpander,
            hideTabs: _isFullscreen,
          );
        }
        final available = constraints.maxWidth - dividerWidth;
        final primaryWidth = (available * controller.splitRatio).clamp(
          minimumPaneWidth,
          available - minimumPaneWidth,
        );
        return Row(
          children: [
            SizedBox(
              width: primaryWidth,
              child: _buildEditorGroup(
                controller,
                WorkspaceEditorGroupId.primary,
                showSidebarExpander: showSidebarExpander,
                hideTabs: _isFullscreen,
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) {
                controller.setSplitRatio(
                  (primaryWidth + details.delta.dx) / available,
                );
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: SizedBox(
                  width: dividerWidth,
                  child: Center(
                    child: VerticalDivider(
                      width: 1,
                      color: Theme.of(context).dividerColor,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _buildEditorGroup(
                controller,
                WorkspaceEditorGroupId.secondary,
                hideTabs: _isFullscreen,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEditorGroup(
    WorkspaceController controller,
    WorkspaceEditorGroupId groupId, {
    bool showSidebarExpander = false,
    bool hideTabs = false,
  }) {
    final selectedEntry = controller.selectedEntry;
    final selectedNovel = controller.selectedNovel;
    final showStructure =
        !hideTabs &&
        groupId == controller.focusedGroupId &&
        selectedNovel != null &&
        switch (selectedEntry?.semanticKind) {
          LibraryEntrySemanticKind.novel ||
          LibraryEntrySemanticKind.body ||
          LibraryEntrySemanticKind.volume => true,
          _ => false,
        };
    final activeDocument = controller.activeDocumentForGroup(groupId);
    final focused = controller.focusedGroupId == groupId;
    final editorGroup = Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => _focusGroup(controller, groupId),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: focused && controller.isSplit
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary.withAlpha(80),
                )
              : null,
        ),
        child: Column(
          children: [
            // 折叠标签行（非移除）保 DocumentPane 下标不变，避免重挂载。
            if (hideTabs)
              const SizedBox.shrink()
            else
              Row(
                children: [
                  if (showSidebarExpander)
                    ColoredBox(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerLowest,
                      child: SizedBox(
                        width: 44,
                        height: DocumentTabs.barHeight,
                        child: IconButton(
                          key: const ValueKey('library-sidebar-expand'),
                          tooltip: '展开侧栏',
                          onPressed: () => setState(() => _showSidebar = true),
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.chevron_right_rounded),
                        ),
                      ),
                    ),
                  Expanded(
                    child: DocumentTabs(
                      controller: controller,
                      groupId: groupId,
                      onActivate: (tab) => _activateTab(controller, tab),
                      onMove: _discardFindReplace,
                      onDragStarted: _startTabDrag,
                      onDragEnded: _finishTabDrag,
                      onClose: (document) =>
                          _closeDocument(controller, document),
                      onContextMenu: (tab, offset) =>
                          _showTabContextMenu(controller, tab, offset),
                    ),
                  ),
                ],
              ),
            if (hideTabs) const SizedBox.shrink() else const Divider(height: 1),
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
                      // hideTabs 仅在全屏为真：文档工具条显示「退出全屏」入口。
                      onToggleFullscreen: hideTabs ? _toggleFullscreen : null,
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
            if (_findController != null &&
                activeDocument != null &&
                groupId == controller.focusedGroupId)
              FindReplaceOverlay(
                findController: _findController!,
                editorController: activeDocument.editorController,
                initialShowReplace: _findReplaceMode,
                onClose: _closeFindReplace,
              ),
          ],
        ),
      ),
    );
    if (!_supportsSplit || !controller.isSplit) {
      return editorGroup;
    }
    return DragTarget<WorkspaceTabDragData>(
      onWillAcceptWithDetails: (details) =>
          details.data.sourceGroupId != groupId,
      onAcceptWithDetails: (details) {
        _discardFindReplace();
        controller.moveTab(details.data.tab, groupId);
        _finishTabDrag();
      },
      builder: (context, candidates, _) => DecoratedBox(
        decoration: BoxDecoration(
          color: candidates.isNotEmpty
              ? Theme.of(context).colorScheme.primaryContainer.withAlpha(55)
              : null,
          border: candidates.isNotEmpty
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                )
              : null,
        ),
        child: editorGroup,
      ),
    );
  }

  void _startTabDrag(WorkspaceTabDragData data) {
    if (_draggingTab == data) {
      return;
    }
    setState(() => _draggingTab = data);
  }

  void _finishTabDrag() {
    if (_draggingTab == null || !mounted) {
      return;
    }
    setState(() => _draggingTab = null);
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

  void _focusGroup(
    WorkspaceController controller,
    WorkspaceEditorGroupId groupId,
  ) {
    if (controller.focusedGroupId == groupId) {
      return;
    }
    _discardFindReplace();
    controller.focusGroup(groupId);
  }

  Future<void> _activateTab(
    WorkspaceController controller,
    WorkspaceTab tab,
  ) async {
    if (controller.activePath != tab.relativePath) {
      _discardFindReplace();
    }
    await controller.activateTab(tab);
  }

  void _discardFindReplace() {
    _findController?.dispose();
    _findController = null;
  }

  /// 切换页面级全屏。进入时丢弃既有查找替换覆盖层（全屏下仍可用 Cmd+F/H 重开）。
  ///
  /// 兜底保留滚动：结构层已让 DocumentPane 不重挂载，但作为防御仍保存所有已挂载
  /// 文档的滚动偏移并在下一帧恢复，覆盖任何漏网的重挂载路径。
  void _toggleFullscreen() {
    // 切换前若有进行中的标签拖拽，先收尾，避免全屏折叠标签行时拖拽源消失的竞态。
    if (_draggingTab != null) {
      _finishTabDrag();
    }
    final controller = ref.read(workspaceControllerProvider(widget.session));
    final savedOffsets = <OpenDocument, double>{};
    for (final tab in controller.tabs) {
      if (tab is OpenDocument && tab.scrollController.hasClients) {
        savedOffsets[tab] = tab.scrollController.offset;
      }
    }
    _discardFindReplace();
    setState(() => _isFullscreen = !_isFullscreen);
    if (savedOffsets.isEmpty) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      // 仅对仍存活的文档恢复：切换期间若文档被异步关闭并 dispose，其
      // scrollController 已不可访问，跳过以免 use-after-dispose。
      final live = <OpenDocument>{};
      for (final tab in controller.tabs) {
        if (tab is OpenDocument) {
          live.add(tab);
        }
      }
      savedOffsets.forEach((doc, offset) {
        if (!live.contains(doc)) {
          return;
        }
        final sc = doc.scrollController;
        if (!sc.hasClients ||
            (sc.offset - offset).abs() <= _scrollRestoreTolerancePx) {
          return;
        }
        sc.jumpTo(offset);
      });
    });
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
    final desktop = switch (defaultTargetPlatform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      _ => false,
    };
    final groupId = controller.groupForTab(tab);
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
        onTap: () =>
            unawaited(_closeBatch(() => controller.closeTabsToRight(tab))),
      ),
      LoreContextMenuItem(
        label: '关闭全部',
        onTap: () =>
            unawaited(_closeBatch(() => controller.closeAllTabsInGroup(tab))),
      ),
      if (desktop && !controller.isSplit)
        LoreContextMenuItem(
          label: '在右侧打开',
          onTap: () {
            _discardFindReplace();
            controller.splitRight(tab);
          },
        ),
      if (desktop &&
          controller.isSplit &&
          groupId == WorkspaceEditorGroupId.primary)
        LoreContextMenuItem(
          label: '移到右侧',
          onTap: () {
            _discardFindReplace();
            controller.moveTab(tab, WorkspaceEditorGroupId.secondary);
          },
        ),
      if (desktop &&
          controller.isSplit &&
          groupId == WorkspaceEditorGroupId.secondary)
        LoreContextMenuItem(
          label: '移到左侧',
          onTap: () {
            _discardFindReplace();
            controller.moveTab(tab, WorkspaceEditorGroupId.primary);
          },
        ),
      if (desktop && controller.isSplit)
        LoreContextMenuItem(
          label: '关闭分屏',
          onTap: () {
            _discardFindReplace();
            controller.closeSplit();
          },
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
    LoreToast.success(context, '已复制路径');
  }

  /// 执行批量关闭；若存在因冲突无法关闭的标签，提示用户先处理。
  Future<void> _closeBatch(Future<List<WorkspaceTab>> Function() action) async {
    final stuck = await action();
    if (!mounted || stuck.isEmpty) {
      return;
    }
    LoreToast.warning(context, '${stuck.length} 个标签因冲突未关闭，请先处理');
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

const double _defaultSidebarWidth = 276;
const double _minimumSidebarWidth = 220;
const double _maximumSidebarWidth = 420;
const double _sidebarResizeHandleWidth = 9;

/// 全屏切换后恢复滚动偏移的容差（像素），小于此值视为无需恢复。
const double _scrollRestoreTolerancePx = 1;
