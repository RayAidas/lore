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
import 'library_failure_snackbar.dart';
import 'library_sidebar.dart';
import 'trash_pane.dart';
import 'workspace_controller.dart';
import 'workspace_editor_group.dart';
import 'workspace_entry_actions.dart';
import 'workspace_inspector.dart';
import 'workspace_platform.dart';

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

  /// [WorkspaceEditorGroup] 的稳定回调集。方法闭包绑定 this，引用的 controller
  /// 用 [_controller]（与 build 中 ref.watch 的实例一致）。
  late final WorkspaceEditorGroupCallbacks _editorGroupCallbacks =
      WorkspaceEditorGroupCallbacks(
        onFocusGroup: (groupId) => _focusGroup(_controller, groupId),
        onExpandSidebar: () => setState(() => _showSidebar = true),
        onActivateTab: (tab) => _activateTab(_controller, tab),
        onDiscardFindReplace: _discardFindReplace,
        onDragStarted: _startTabDrag,
        onDragEnded: _finishTabDrag,
        onCloseTab: (tab) => _closeDocument(_controller, tab),
        onContextMenu: (tab, offset) => showWorkspaceTabContextMenu(
          context: context,
          controller: _controller,
          tab: tab,
          position: offset,
          onClose: (t) => _closeDocument(_controller, t),
          onSplitChanged: _discardFindReplace,
        ),
        onStructureFailure: _showFailure,
        onReloadConflict: (doc) => _reloadConflict(_controller, doc),
        onToggleFullscreen: _toggleFullscreen,
        onCloseFindReplace: _closeFindReplace,
      );

  WorkspaceController get _controller {
    return ref.read(workspaceControllerProvider(widget.session));
  }

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
    if (!supportsDesktopSplit && _controller.isSplit) {
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
            final desktop = supportsDesktopSplit;
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
                const SingleActivator(
                  LogicalKeyboardKey.comma,
                  meta: true,
                ): () {
                  showSettingsPanel(context);
                },
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
                              onPressed: () =>
                                  showTrashPanel(context, controller),
                              tooltip: '回收站',
                              icon: const Icon(Icons.delete_outline),
                            ),
                            IconButton(
                              onPressed: () => showSettingsPanel(context),
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
      return _editorGroup(
        controller,
        WorkspaceEditorGroupId.primary,
        showSidebarExpander: showSidebarExpander,
        hideTabs: _isFullscreen,
      );
    }
    if (!controller.isSplit) {
      final editorGroup = _editorGroup(
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
          return _editorGroup(
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
              child: _editorGroup(
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
              child: _editorGroup(
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

  /// 构造单个编辑分组组件，填入页面级稳定参数（session/findController/callbacks），
  /// 调用点只需给 controller/groupId/showSidebarExpander/hideTabs。分组的具体呈现
  /// （标签行 + DocumentPane + 查找替换 + 分屏 DragTarget）见 [WorkspaceEditorGroup]。
  Widget _editorGroup(
    WorkspaceController controller,
    WorkspaceEditorGroupId groupId, {
    bool showSidebarExpander = false,
    bool hideTabs = false,
  }) {
    return WorkspaceEditorGroup(
      controller: controller,
      groupId: groupId,
      session: widget.session,
      showSidebarExpander: showSidebarExpander,
      hideTabs: hideTabs,
      findController: _findController,
      findReplaceMode: _findReplaceMode,
      callbacks: _editorGroupCallbacks,
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
