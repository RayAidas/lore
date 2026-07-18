import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:path/path.dart' as p;

import '../preferences/preferences_providers.dart';
import 'library_failure_snackbar.dart';
import 'name_prompt_dialog.dart';
import 'workspace_controller.dart';
import 'workspace_directory_tree.dart';

/// 目录树右键菜单的可选动作。
enum _ContextMenuAction {
  open,
  newFolder,
  newText,
  newMarkdown,
  rename,
  copyPath,
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
    super.key,
  });

  final WorkspaceController controller;
  final String displayPath;
  final VoidCallback onSelectLibrary;
  final BuildContext? drawerContext;

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
          await widget.controller.registerExistingNovel(title.trim());
        } on LibraryOperationException catch (registerError) {
          _showFailure(registerError.failure);
        }
      }
    }
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

  Future<void> _deleteSelected() async {
    final entry = widget.controller.selectedEntry;
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
        await widget.controller.deleteSelectedEntry();
      } on LibraryOperationException catch (error) {
        _showFailure(error.failure);
      }
    }
  }

  Future<void> _renameSelected() async {
    final entry = widget.controller.selectedEntry;
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
          widget.controller.renameNovel(novelId, name),
        LibraryEntrySemanticKind.body when novelId != null =>
          widget.controller.renameBody(novelId, name),
        LibraryEntrySemanticKind.volume || LibraryEntrySemanticKind.chapter
            when novelId != null && entry.semanticId != null =>
          widget.controller.renameContentNode(
            novelId,
            ContentId(entry.semanticId!),
            name,
          ),
        _ => widget.controller.renameSelected(name),
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
      builder: (context) => NamePromptDialog(
        title: title,
        label: label,
        initialValue: initialValue,
        suffix: suffix,
      ),
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

  Future<void> _handleContextMenu(LibraryEntry entry, Offset position) async {
    if (!mounted) {
      return;
    }
    // 路径 A：先选中目标，复用基于 selectedEntry 的重命名/删除/新建逻辑。
    widget.controller.selectEntry(entry);
    final action = await showMenu<_ContextMenuAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      constraints: const BoxConstraints(minWidth: 184, maxWidth: 224),
      items: _buildMenuItems(entry),
    );
    if (action == null || !mounted) {
      return;
    }
    await _invokeContextMenuAction(action, entry);
  }

  List<PopupMenuEntry<_ContextMenuAction>> _buildMenuItems(LibraryEntry entry) {
    final isDir = entry.isDirectory;
    final isPlainDir = isDir && entry.semanticKind == null;
    final canOpen = !isDir && entry.type != LibraryEntryType.otherFile;
    final isSemantic = entry.semanticKind != null;
    return <PopupMenuEntry<_ContextMenuAction>>[
      if (canOpen) ...[
        PopupMenuItem(
          value: _ContextMenuAction.open,
          height: _popupMenuItemHeight,
          child: _menuLabel('打开'),
        ),
      ],
      if (isPlainDir) ...[
        PopupMenuItem(
          value: _ContextMenuAction.newFolder,
          height: _popupMenuItemHeight,
          child: _menuLabel('新建子文件夹'),
        ),
        PopupMenuItem(
          value: _ContextMenuAction.newText,
          height: _popupMenuItemHeight,
          child: _menuLabel('新建 TXT'),
        ),
        PopupMenuItem(
          value: _ContextMenuAction.newMarkdown,
          height: _popupMenuItemHeight,
          child: _menuLabel('新建 Markdown'),
        ),
      ],
      PopupMenuItem(
        value: _ContextMenuAction.rename,
        height: _popupMenuItemHeight,
        child: _menuLabel('重命名'),
      ),
      PopupMenuItem(
        value: _ContextMenuAction.copyPath,
        height: _popupMenuItemHeight,
        child: _menuLabel('复制路径'),
      ),
      PopupMenuItem(
        value: _ContextMenuAction.delete,
        enabled: !isSemantic,
        height: _popupMenuItemHeight,
        child: _menuLabel('移到回收站', destructive: !isSemantic),
      ),
    ];
  }

  Future<void> _invokeContextMenuAction(
    _ContextMenuAction action,
    LibraryEntry entry,
  ) async {
    switch (action) {
      case _ContextMenuAction.open:
        await _openPath(entry.relativePath);
      case _ContextMenuAction.newFolder:
        await _createDirectory();
      case _ContextMenuAction.newText:
        await _createDocument(DocumentFormat.text);
      case _ContextMenuAction.newMarkdown:
        await _createDocument(DocumentFormat.markdown);
      case _ContextMenuAction.rename:
        await _renameSelected();
      case _ContextMenuAction.delete:
        await _deleteSelected();
      case _ContextMenuAction.copyPath:
        await Clipboard.setData(ClipboardData(text: entry.relativePath));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('已复制路径'),
              duration: Duration(seconds: 2),
            ),
          );
        }
    }
  }

  Widget _menuLabel(String label, {bool destructive = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Text(
      label,
      style: TextStyle(
        color: destructive ? colorScheme.error : colorScheme.onSurface,
      ),
    );
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
              padding: const EdgeInsets.fromLTRB(20, 18, 10, 12),
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
                      _SidebarMenuItem(
                        label: '新建小说',
                        onPressed: () => unawaited(_createNovel()),
                      ),
                      _SidebarMenuItem(
                        label: '新建文件夹',
                        onPressed: () => unawaited(_createDirectory()),
                      ),
                      _SidebarMenuItem(
                        label: '新建 TXT',
                        onPressed: () =>
                            unawaited(_createDocument(DocumentFormat.text)),
                      ),
                      _SidebarMenuItem(
                        label: '新建 Markdown',
                        onPressed: () =>
                            unawaited(_createDocument(DocumentFormat.markdown)),
                      ),
                    ],
                  ),
                  if (controller.selectedEntry != null)
                    _SidebarMenuButton(
                      tooltip: '更多操作',
                      icon: Icons.more_horiz_rounded,
                      menuChildren: [
                        _SidebarMenuItem(
                          label: '重命名',
                          onPressed: () => unawaited(_renameSelected()),
                        ),
                        _SidebarMenuItem(
                          label: '移到回收站',
                          destructive: true,
                          onPressed: () => unawaited(_deleteSelected()),
                        ),
                      ],
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
                          unawaited(_handleContextMenu(entry, offset)),
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
                    tooltip: '重新选择书库',
                    onPressed: () => unawaited(_selectLibrary()),
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
      alignmentOffset: const Offset(
        _sidebarMenuButtonSize - _sidebarMenuWidth,
        6,
      ),
      onOpen: () => setState(() => _isOpen = true),
      onClose: () => setState(() => _isOpen = false),
      style: MenuStyle(
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
            style: IconButton.styleFrom(
              minimumSize: const Size.square(_sidebarMenuButtonSize),
              maximumSize: const Size.square(_sidebarMenuButtonSize),
              padding: EdgeInsets.zero,
              hoverColor: colorScheme.onSurface.withValues(alpha: 0.06),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
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

final class _SidebarMenuItem extends StatelessWidget {
  const _SidebarMenuItem({
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foregroundColor = destructive
        ? colorScheme.error
        : colorScheme.onSurface;
    return MenuItemButton(
      onPressed: onPressed,
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(foregroundColor),
        overlayColor: WidgetStatePropertyAll(
          destructive
              ? colorScheme.error.withValues(alpha: 0.08)
              : colorScheme.onSurface.withValues(alpha: 0.055),
        ),
      ),
      child: Text(label),
    );
  }
}

const double _sidebarMenuButtonSize = 36;
const double _sidebarMenuWidth = 184;
const double _popupMenuItemHeight = 34;
