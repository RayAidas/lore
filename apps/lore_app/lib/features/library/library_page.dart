import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';

import 'library_providers.dart';

class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(libraryControllerProvider);
    return value.when(
      loading: () => const _LoadingPage(),
      error: (error, stackTrace) => _UnexpectedErrorPage(
        onRetry: ref.read(libraryControllerProvider.notifier).retryRestore,
      ),
      data: (state) => switch (state) {
        LibraryNeedsSelectionState() => _SelectionPage(
          onSelect: () => _selectDirectory(context, ref),
        ),
        LibraryNeedsInitializationState current => _InitializationPage(
          state: current,
          onConfirm: () =>
              ref.read(libraryControllerProvider.notifier).initialize(current),
          onCancel: () => ref
              .read(libraryControllerProvider.notifier)
              .cancelInitialization(current),
        ),
        LibraryReadyState ready => _LibraryWorkspace(
          state: ready,
          onSelectLibrary: () => _selectDirectory(context, ref),
        ),
        LibraryErrorState error => _LibraryErrorPage(
          state: error,
          onRetry: ref.read(libraryControllerProvider.notifier).retryRestore,
          onSelect: () => _selectDirectory(context, ref),
          onReturn: error.previous == null
              ? null
              : () => ref
                    .read(libraryControllerProvider.notifier)
                    .returnToPrevious(error.previous!),
        ),
      },
    );
  }

  Future<void> _selectDirectory(BuildContext context, WidgetRef ref) async {
    final next = await ref
        .read(libraryControllerProvider.notifier)
        .selectDirectory();
    if (!context.mounted || next is! LibraryNeedsInitializationState) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('初始化书库？'),
          content: Text(
            '“${next.access.displayPath}”还不是 Lore 书库。初始化只会添加 .lore 元数据，不会修改现有文件。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('初始化'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await ref.read(libraryControllerProvider.notifier).initialize(next);
    } else {
      await ref
          .read(libraryControllerProvider.notifier)
          .cancelInitialization(next);
    }
  }
}

class _LoadingPage extends StatelessWidget {
  const _LoadingPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _SelectionPage extends StatelessWidget {
  const _SelectionPage({required this.onSelect});

  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lore')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.menu_book_outlined, size: 56),
                const SizedBox(height: 20),
                Text(
                  '选择你的书库',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  '书库是保存小说、资料和灵感的本地文件夹。Lore 不会将内容上传到云端。',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onSelect,
                  icon: const Icon(Icons.folder_open_outlined),
                  label: const Text('选择书库目录'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InitializationPage extends StatelessWidget {
  const _InitializationPage({
    required this.state,
    required this.onConfirm,
    required this.onCancel,
  });

  final LibraryNeedsInitializationState state;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lore')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.create_new_folder_outlined, size: 48),
                const SizedBox(height: 16),
                Text('初始化书库', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                Text(state.access.displayPath, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                const Text('初始化只会创建 .lore/library.json，不会修改目录中的现有文件。'),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  children: [
                    OutlinedButton(
                      onPressed: onCancel,
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      onPressed: onConfirm,
                      child: const Text('初始化'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LibraryErrorPage extends StatelessWidget {
  const _LibraryErrorPage({
    required this.state,
    required this.onRetry,
    required this.onSelect,
    this.onReturn,
  });

  final LibraryErrorState state;
  final VoidCallback onRetry;
  final VoidCallback onSelect;
  final VoidCallback? onReturn;

  @override
  Widget build(BuildContext context) {
    final unsupported =
        state.failure.code == LibraryFailureCode.platformUnsupported;
    return Scaffold(
      appBar: AppBar(title: const Text('Lore')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  unsupported
                      ? Icons.phone_android_outlined
                      : Icons.error_outline,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  unsupported ? '当前平台暂未支持' : '无法打开书库',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(state.failure.message, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    if (!unsupported)
                      OutlinedButton(
                        onPressed: onRetry,
                        child: const Text('重试'),
                      ),
                    if (!unsupported)
                      FilledButton(
                        onPressed: onSelect,
                        child: const Text('选择其他目录'),
                      ),
                    if (onReturn != null)
                      TextButton(
                        onPressed: onReturn,
                        child: const Text('返回当前书库'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UnexpectedErrorPage extends StatelessWidget {
  const _UnexpectedErrorPage({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('启动书库时发生了意外错误。'),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

class _LibraryWorkspace extends StatefulWidget {
  const _LibraryWorkspace({required this.state, required this.onSelectLibrary});

  final LibraryReadyState state;
  final VoidCallback onSelectLibrary;

  @override
  State<_LibraryWorkspace> createState() => _LibraryWorkspaceState();
}

class _LibraryWorkspaceState extends State<_LibraryWorkspace> {
  String? _selectedPath;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lore'),
        actions: [
          IconButton(
            onPressed: widget.onSelectLibrary,
            tooltip: '重新选择书库',
            icon: const Icon(Icons.drive_folder_upload_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Text(
              widget.state.session.access.displayPath,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: 300,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                          child: Text(
                            '书库',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Expanded(
                          child: _LibraryDirectory(
                            session: widget.state.session,
                            relativePath: '',
                            selectedPath: _selectedPath,
                            onSelected: (path) {
                              setState(() => _selectedPath = path);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Center(child: Text(_selectedPath ?? '选择文件开始写作')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryDirectory extends ConsumerStatefulWidget {
  const _LibraryDirectory({
    required this.session,
    required this.relativePath,
    required this.selectedPath,
    required this.onSelected,
  });

  final LibrarySession session;
  final String relativePath;
  final String? selectedPath;
  final ValueChanged<String> onSelected;

  @override
  ConsumerState<_LibraryDirectory> createState() => _LibraryDirectoryState();
}

class _LibraryDirectoryState extends ConsumerState<_LibraryDirectory> {
  late Future<List<LibraryEntry>> _entries;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant _LibraryDirectory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session ||
        oldWidget.relativePath != widget.relativePath) {
      _reload();
    }
  }

  void _reload() {
    _entries = ref
        .read(libraryControllerProvider.notifier)
        .listChildren(widget.session, relativePath: widget.relativePath);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LibraryEntry>>(
      future: _entries,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return widget.relativePath.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : const Padding(
                  padding: EdgeInsets.all(12),
                  child: LinearProgressIndicator(),
                );
        }
        if (snapshot.hasError) {
          return Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(_reload),
              child: const Text('目录加载失败，点击重试'),
            ),
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
            return _DirectoryEntryTile(
              entry: entry,
              session: widget.session,
              selectedPath: widget.selectedPath,
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
            onTap: () => widget.onSelected(entry.relativePath),
          );
        }).toList();
        if (widget.relativePath.isEmpty) {
          return ListView(
            padding: const EdgeInsets.only(bottom: 12),
            children: children,
          );
        }
        return Column(mainAxisSize: MainAxisSize.min, children: children);
      },
    );
  }
}

class _DirectoryEntryTile extends StatefulWidget {
  const _DirectoryEntryTile({
    required this.entry,
    required this.session,
    required this.selectedPath,
    required this.onSelected,
  });

  final LibraryEntry entry;
  final LibrarySession session;
  final String? selectedPath;
  final ValueChanged<String> onSelected;

  @override
  State<_DirectoryEntryTile> createState() => _DirectoryEntryTileState();
}

class _DirectoryEntryTileState extends State<_DirectoryEntryTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      dense: true,
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
      },
      children: _expanded
          ? [
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: _LibraryDirectory(
                  session: widget.session,
                  relativePath: widget.entry.relativePath,
                  selectedPath: widget.selectedPath,
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
