import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_ui/lore_ui.dart';
import 'package:path/path.dart' as p;

import '../preferences/preferences_providers.dart';
import '../import_export/export_panel.dart';
import '../import_export/import_flow.dart';
import 'library_failure_snackbar.dart';
import 'trash_pane.dart';
import 'workspace_controller.dart';
import 'workspace_directory_tree.dart';
import 'workspace_entry_actions.dart';

/// 目录树右键菜单的可选动作。
enum _ContextMenuAction {
  newFolder,
  newText,
  newMarkdown,
  newVolume,
  newChapter,
  revealInFinder,
  rename,
  copyPath,
  export,
  delete,
}

/// 工作区左侧栏：标题、新建/重命名/删除、目录树、书库路径与切换。
///
/// 自带新建/重命名/删除等交互逻辑（弹窗、失败提示），这些逻辑需要各自的
/// `context`/`ref`/`mounted`，因此侧栏作为 [ConsumerStatefulWidget] 独立持有。
final class LibrarySidebar extends ConsumerStatefulWidget {
  const LibrarySidebar({
    required this.controller,
    required this.displayPath,
    required this.onSelectLibrary,
    this.drawerContext,
    this.onCollapse,
    super.key,
  });

  final WorkspaceController controller;
  final String displayPath;
  final VoidCallback onSelectLibrary;
  final BuildContext? drawerContext;
  final VoidCallback? onCollapse;

  @override
  ConsumerState<LibrarySidebar> createState() => _LibrarySidebarState();
}

final class _LibrarySidebarState extends ConsumerState<LibrarySidebar> {
  Future<void> _createNovel() async {
    final title = await _promptName(title: '新建小说', label: '书名');
    if (title == null) {
      return;
    }
    final prefs =
        ref.read(appPreferencesProvider).value ?? AppPreferences.defaults();
    try {
      await widget.controller.createNovel(
        title,
        chapterFormat: prefs.defaultChapterFormat,
      );
    } on LibraryOperationException catch (error) {
      if (error.failure.code != LibraryFailureCode.alreadyExists || !mounted) {
        _showFailure(error.failure);
        return;
      }
      final register = await showLoreConfirmDialog(
        context: context,
        title: '同名目录已存在',
        message: '是否将“${title.trim()}”注册为小说并扫描其中的正文？',
        cancelLabel: '修改书名',
        confirmLabel: '注册现有目录',
      );
      if (register) {
        try {
          await widget.controller.registerExistingNovel(title.trim());
        } on LibraryOperationException catch (registerError) {
          _showFailure(registerError.failure);
        }
      }
    }
  }

  Future<void> _importTxt() {
    return importTxtNovelFlow(context, widget.controller);
  }

  Future<void> _exportEntry(LibraryEntry entry) async {
    final novelId = entry.novelId;
    if (novelId == null) {
      return;
    }
    await showExportPanel(
      context: context,
      controller: widget.controller,
      novelId: NovelId(novelId),
      volumeId:
          entry.semanticKind == LibraryEntrySemanticKind.volume &&
              entry.semanticId != null
          ? ContentId(entry.semanticId!)
          : null,
    );
  }

  Future<void> _createDirectory() async {
    final name = await _promptName(title: '新建文件夹', label: '文件夹名称');
    if (name == null) {
      return;
    }
    try {
      await widget.controller.createDirectory(
        parentPath: _creationParentPath(),
        name: name,
      );
    } on LibraryOperationException catch (error) {
      _showFailure(error.failure);
    }
  }

  Future<void> _createDocument(DocumentFormat format) async {
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
      await widget.controller.createDocument(
        parentPath: _creationParentPath(),
        name: name,
        format: format,
      );
    } on LibraryOperationException catch (error) {
      _showFailure(error.failure);
    }
  }

  Future<void> _deleteSelected(LibraryEntry entry) async {
    switch (entry.semanticKind) {
      case LibraryEntrySemanticKind.body:
        // 不可达：右键菜单不渲染 body 的删除入口。保留为 exhaustive 覆盖。
        return;
      case LibraryEntrySemanticKind.novel:
        if (!mounted) {
          return;
        }
        final novelConfirmed = await showLoreTypeToConfirmDialog(
          context: context,
          title: '删除整本小说？',
          message: '“${entry.name}”及其所有卷、章节将移到回收站，可在回收站恢复。',
          expectedText: entry.name,
          helperText: '请输入小说名 “${entry.name}” 以确认。',
        );
        if (!novelConfirmed || !mounted) {
          return;
        }
        await _invokeDelete(
          () => widget.controller.deleteNovel(NovelId(entry.novelId!)),
        );
        return;
      case LibraryEntrySemanticKind.volume:
        await _confirmAndDelete(
          entry,
          () => widget.controller.deleteContentNode(
            NovelId(entry.novelId!),
            ContentId(entry.semanticId!),
          ),
        );
        return;
      case LibraryEntrySemanticKind.chapter:
      case null:
        // 文档文件（章节/散文件）：走共享删除流程，与标签栏右键菜单共用。
        await deleteDocumentFlow(
          context: context,
          controller: widget.controller,
          relativePath: entry.relativePath,
          displayName: entry.name,
        );
        return;
    }
  }

  /// 弹普通删除确认对话框，确认后执行 [action]；取消或 widget 已卸载则跳过。
  Future<void> _confirmAndDelete(
    LibraryEntry entry,
    Future<DeletionResult> Function() action,
  ) async {
    if (!mounted) {
      return;
    }
    final confirmed = await showLoreConfirmDialog(
      context: context,
      title: '删除？',
      message: '“${entry.name}”将移到回收站，可在回收站恢复。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!confirmed || !mounted) {
      return;
    }
    await _invokeDelete(action);
  }

  /// 执行删除并统一把 [LibraryOperationException] 转成失败提示。
  Future<void> _invokeDelete(Future<DeletionResult> Function() action) async {
    try {
      await action();
    } on LibraryOperationException catch (error) {
      _showFailure(error.failure);
    }
  }

  Future<void> _renameSelected(LibraryEntry entry) async {
    // 文档文件（章节/散文件）：走共享文档重命名流程——按路径判断走结构服务或
    // 普通重命名，与标签栏右键菜单共用同一入口，避免两处复制分支逻辑。
    if (!entry.isDirectory && entry.type != LibraryEntryType.otherFile) {
      await renameDocumentFlow(
        context: context,
        controller: widget.controller,
        relativePath: entry.relativePath,
        displayName: entry.name,
      );
      return;
    }
    // 目录型结构节点（小说/正文/卷）：统一 prompt + 专用结构方法。
    final name = await _promptName(
      title: '重命名',
      label: '新名称',
      initialValue: entry.name,
    );
    if (name == null) {
      return;
    }
    await _runMutation(() async {
      final novelId = entry.novelId == null ? null : NovelId(entry.novelId!);
      await switch (entry.semanticKind) {
        LibraryEntrySemanticKind.novel when novelId != null =>
          widget.controller.renameNovel(novelId, name),
        LibraryEntrySemanticKind.body when novelId != null =>
          widget.controller.renameBody(novelId, name),
        LibraryEntrySemanticKind.volume
            when novelId != null && entry.semanticId != null =>
          widget.controller.renameContentNode(
            novelId,
            ContentId(entry.semanticId!),
            name,
          ),
        _ => widget.controller.renameSelected(name),
      };
    });
  }

  Future<String?> _promptName({
    required String title,
    required String label,
    String initialValue = '',
    String? suffix,
  }) {
    return showLoreTextPromptDialog(
      context: context,
      title: title,
      label: label,
      initialValue: initialValue,
      suffixText: suffix,
    );
  }

  Future<void> _openPath(String relativePath) async {
    try {
      await widget.controller.openPath(relativePath);
    } on LibraryOperationException catch (error) {
      _showFailure(error.failure);
    }
  }

  Future<void> _selectLibrary() async {
    if (await widget.controller.flushAll()) {
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

  String _creationParentPath() {
    final entry = widget.controller.selectedEntry;
    if (entry == null) {
      return '';
    }
    if (entry.isDirectory) {
      return entry.relativePath;
    }
    final parent = p.dirname(entry.relativePath);
    return parent == '.' ? '' : parent;
  }

  void _showFailure(LibraryFailure failure) {
    if (!mounted) {
      return;
    }
    showLibraryFailure(context, failure);
  }

  @override
  void dispose() {
    // 侧栏卸载时确保覆盖层菜单一并移除，避免悬挂 overlay。
    ContextMenuController.removeAny();
    super.dispose();
  }

  /// 右键/长按触发：在 [position] 处弹出上下文菜单。
  ///
  /// 菜单由 [showLoreContextMenu] 呈现（基于 `ContextMenuController`+`TapRegion`，
  /// 非模态、不吞指针）：任意时刻仅一个菜单，菜单已弹出时再次右键其他条目，
  /// 同一次点击即可关闭旧菜单并打开新菜单（与 Obsidian 等原生行为一致），也
  /// 消除右键误触打开视图的时序边界。
  void _showContextMenu(LibraryEntry entry, Offset position) {
    if (!mounted) {
      return;
    }
    // 右键不应切换中间视图。novel/body/volume 的选中会让中间区域切到结构面板，
    // 而这些条目的菜单动作（新建子节点/重命名/删除）都基于 entry 本身、不依赖
    // 选中态——因此对它们跳过选中。其余条目（散文件/章节/普通目录）选中不会
    // 引起视图切换，仍同步选中以复用 rename/delete/新建里基于 selectedEntry 的逻辑。
    final drivesStructurePane = switch (entry.semanticKind) {
      LibraryEntrySemanticKind.novel ||
      LibraryEntrySemanticKind.body ||
      LibraryEntrySemanticKind.volume => true,
      _ => false,
    };
    if (!drivesStructurePane) {
      widget.controller.selectEntry(entry);
    }
    showLoreContextMenu(
      context: context,
      position: position,
      items: _buildContextMenuItems(entry),
    );
  }

  List<LoreContextMenuItem> _buildContextMenuItems(LibraryEntry entry) {
    final isDir = entry.isDirectory;
    final isPlainDir = isDir && entry.semanticKind == null;
    final canDelete = entry.semanticKind != LibraryEntrySemanticKind.body;
    final canCreateVolume =
        entry.semanticKind == LibraryEntrySemanticKind.novel ||
        entry.semanticKind == LibraryEntrySemanticKind.body;
    final canCreateChapter =
        entry.semanticKind == LibraryEntrySemanticKind.volume;
    LoreContextMenuItem item(
      String label,
      _ContextMenuAction action, {
      bool destructive = false,
    }) => LoreContextMenuItem(
      label: label,
      destructive: destructive,
      onTap: () => unawaited(_invokeContextMenuAction(action, entry)),
    );

    return <LoreContextMenuItem>[
      if (canCreateVolume) item('新建卷', _ContextMenuAction.newVolume),
      if (canCreateChapter) item('新建章节', _ContextMenuAction.newChapter),
      if (isPlainDir) ...[
        item('新建子文件夹', _ContextMenuAction.newFolder),
        item('新建 TXT', _ContextMenuAction.newText),
        item('新建 Markdown', _ContextMenuAction.newMarkdown),
      ],
      item('重命名', _ContextMenuAction.rename),
      if (entry.semanticKind == LibraryEntrySemanticKind.novel ||
          entry.semanticKind == LibraryEntrySemanticKind.body ||
          entry.semanticKind == LibraryEntrySemanticKind.volume)
        item('导出章节', _ContextMenuAction.export),
      item('复制路径', _ContextMenuAction.copyPath),
      if (widget.controller.revealGateway != null)
        item('在 Finder 中显示', _ContextMenuAction.revealInFinder),
      if (canDelete)
        item('移到回收站', _ContextMenuAction.delete, destructive: true),
    ];
  }

  Future<void> _invokeContextMenuAction(
    _ContextMenuAction action,
    LibraryEntry entry,
  ) async {
    switch (action) {
      case _ContextMenuAction.newFolder:
        await _createDirectory();
      case _ContextMenuAction.newText:
        await _createDocument(DocumentFormat.text);
      case _ContextMenuAction.newMarkdown:
        await _createDocument(DocumentFormat.markdown);
      case _ContextMenuAction.newVolume:
        await _runMutation(
          () => widget.controller.createVolume(NovelId(entry.novelId!)),
        );
      case _ContextMenuAction.newChapter:
        await _runMutation(
          () => widget.controller.createChapter(
            NovelId(entry.novelId!),
            volumeId: entry.semanticKind == LibraryEntrySemanticKind.volume
                ? ContentId(entry.semanticId!)
                : null,
          ),
        );
      case _ContextMenuAction.revealInFinder:
        await _runMutation(
          () => widget.controller.revealEntry(entry.relativePath),
        );
      case _ContextMenuAction.rename:
        await _renameSelected(entry);
      case _ContextMenuAction.export:
        await _exportEntry(entry);
      case _ContextMenuAction.delete:
        await _deleteSelected(entry);
      case _ContextMenuAction.copyPath:
        await Clipboard.setData(ClipboardData(text: entry.relativePath));
        if (mounted) {
          LoreToast.success(context, '已复制路径');
        }
    }
  }

  /// 执行结构操作/reveal 并统一把 [LibraryOperationException] 转成失败提示。
  Future<void> _runMutation(Future<dynamic> Function() action) async {
    try {
      await action();
    } on LibraryOperationException catch (error) {
      _showFailure(error.failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final controller = widget.controller;
    return Material(
      color: colorScheme.surfaceContainerLow,
      child: SafeArea(
        top: widget.drawerContext != null,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '书库',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  _SidebarMenuButton(
                    tooltip: '新建',
                    icon: Icons.add_rounded,
                    menuChildren: [
                      LoreMenuItemButton(
                        label: '新建小说',
                        onPressed: () => unawaited(_createNovel()),
                      ),
                      LoreMenuItemButton(
                        label: '新建文件夹',
                        onPressed: () => unawaited(_createDirectory()),
                      ),
                      LoreMenuItemButton(
                        label: '新建 TXT',
                        onPressed: () =>
                            unawaited(_createDocument(DocumentFormat.text)),
                      ),
                      LoreMenuItemButton(
                        label: '新建 Markdown',
                        onPressed: () =>
                            unawaited(_createDocument(DocumentFormat.markdown)),
                      ),
                    ],
                  ),
                  IconButton(
                    tooltip: '导入 TXT',
                    onPressed: () => unawaited(_importTxt()),
                    icon: const Icon(Icons.file_download_outlined, size: 20),
                    style: _sidebarIconButtonStyle(colorScheme),
                  ),
                  if (widget.onCollapse case final onCollapse?)
                    IconButton(
                      key: const ValueKey('library-sidebar-collapse'),
                      tooltip: '收起侧栏',
                      onPressed: onCollapse,
                      style: _sidebarIconButtonStyle(colorScheme),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                ],
              ),
            ),
            Expanded(
              child: controller.initialized
                  ? WorkspaceDirectory(
                      controller: controller,
                      relativePath: '',
                      selectedPath: controller.selectedPath,
                      reloadToken: controller.treeRevision,
                      onSelected: (entry) {
                        controller.selectEntry(entry);
                        if (!entry.isDirectory &&
                            entry.type != LibraryEntryType.otherFile) {
                          unawaited(_openPath(entry.relativePath));
                          if (widget.drawerContext != null) {
                            Navigator.of(widget.drawerContext!).pop();
                          }
                        }
                      },
                      onContextMenu: (entry, offset) =>
                          _showContextMenu(entry, offset),
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 7, 8, 7),
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
                      message: widget.displayPath,
                      child: Text(
                        widget.displayPath,
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
                    tooltip: '回收站',
                    onPressed: () {
                      unawaited(showTrashPanel(context, widget.controller));
                      // drawer 模式下顺手关闭抽屉：先 push 面板（盖在 drawer 之上），
                      // 再 pop drawer，关闭面板后直接回到工作区而非 drawer。
                      if (widget.drawerContext != null) {
                        Navigator.of(widget.drawerContext!).pop();
                      }
                    },
                    icon: const Icon(Icons.delete_outline, size: 18),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: '重新选择书库',
                    onPressed: () => unawaited(_selectLibrary()),
                    icon: const Icon(
                      Icons.drive_folder_upload_outlined,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _SidebarMenuButton extends StatefulWidget {
  const _SidebarMenuButton({
    required this.tooltip,
    required this.icon,
    required this.menuChildren,
  });

  final String tooltip;
  final IconData icon;
  final List<Widget> menuChildren;

  @override
  State<_SidebarMenuButton> createState() => _SidebarMenuButtonState();
}

final class _SidebarMenuButtonState extends State<_SidebarMenuButton> {
  bool _isOpen = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return MenuAnchor(
      animated: true,
      alignmentOffset: const Offset(0, 6),
      onOpen: () => setState(() => _isOpen = true),
      onClose: () => setState(() => _isOpen = false),
      style: MenuStyle(
        alignment: AlignmentDirectional.bottomStart,
        fixedSize: const WidgetStatePropertyAll(
          Size.fromWidth(_sidebarMenuWidth),
        ),
      ),
      menuChildren: widget.menuChildren,
      builder: (context, menuController, child) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: _isOpen
                ? colorScheme.primaryContainer.withValues(alpha: 0.72)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isOpen
                  ? colorScheme.primary.withValues(alpha: 0.12)
                  : Colors.transparent,
            ),
          ),
          child: IconButton(
            tooltip: widget.tooltip,
            onPressed: () {
              if (menuController.isOpen) {
                menuController.close();
              } else {
                menuController.open();
              }
            },
            style: _sidebarIconButtonStyle(colorScheme),
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.82, end: 1).animate(animation),
                  child: child,
                ),
              ),
              child: Icon(
                widget.icon,
                key: ValueKey(_isOpen),
                size: 20,
                color: _isOpen
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      },
    );
  }
}

const double _sidebarMenuButtonSize = 36;
const double _sidebarMenuWidth = 184;

ButtonStyle _sidebarIconButtonStyle(ColorScheme colorScheme) {
  return IconButton.styleFrom(
    minimumSize: const Size.square(_sidebarMenuButtonSize),
    maximumSize: const Size.square(_sidebarMenuButtonSize),
    padding: EdgeInsets.zero,
    hoverColor: colorScheme.onSurface.withValues(alpha: 0.06),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );
}
