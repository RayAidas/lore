import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_ui/lore_ui.dart';

import 'library_providers.dart';
import '../preferences/settings_page.dart';
import '../workspace/library_workspace_page.dart';

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
        LibraryReadyState ready => LibraryWorkspacePage(
          session: ready.session,
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
    final confirmed = await showLoreConfirmDialog(
      context: context,
      title: '初始化书库？',
      message:
          '“${next.access.displayPath}”还不是 Lore 书库。初始化只会添加 .lore 元数据，不会修改现有文件。',
      confirmLabel: '初始化',
    );
    if (confirmed) {
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
      appBar: AppBar(
        title: const Text('Lore'),
        actions: [
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => showSettingsPanel(context),
          ),
        ],
      ),
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
