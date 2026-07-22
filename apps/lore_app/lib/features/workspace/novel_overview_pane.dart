import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';

import '../library/library_providers.dart';
import '../preferences/preferences_providers.dart';
import 'workspace_controller.dart';

/// 小说概览页：封面、简介、统计卡片、卷摘要。
class NovelOverviewPage extends ConsumerStatefulWidget {
  const NovelOverviewPage({
    required this.controller,
    required this.novelId,
    super.key,
  });

  final WorkspaceController controller;
  final NovelId novelId;

  @override
  ConsumerState<NovelOverviewPage> createState() => _NovelOverviewPageState();
}

final class _NovelOverviewPageState extends ConsumerState<NovelOverviewPage> {
  Future<NovelOverview>? _future;
  int _lastTreeRevision = -1;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant NovelOverviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller.treeRevision != _lastTreeRevision ||
        widget.novelId != oldWidget.novelId) {
      _reload();
    }
  }

  void _reload() {
    _lastTreeRevision = widget.controller.treeRevision;
    final goal = ref.read(appPreferencesProvider).value?.dailyWordGoal ?? 0;
    _future = widget.controller.loadNovelOverview(
      widget.novelId,
      dailyWordGoal: goal,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        if (widget.controller.treeRevision != _lastTreeRevision) {
          _reload();
        }
        return FutureBuilder<NovelOverview>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('$snapshot.error'),
                ),
              );
            }
            final overview = snapshot.data!;
            return _OverviewContent(
              overview: overview,
              session: widget.controller.session,
              assetService: ref.watch(libraryAssetServiceProvider),
            );
          },
        );
      },
    );
  }
}

final class _OverviewContent extends StatelessWidget {
  const _OverviewContent({
    required this.overview,
    required this.session,
    required this.assetService,
  });

  final NovelOverview overview;
  final LibrarySession session;
  final LibraryAssetService assetService;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metadata = overview.metadata;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Cover(
                    session: session,
                    assetService: assetService,
                    novelRoot: overview.rootPath,
                    coverPath: metadata.coverPath,
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          metadata.title,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          metadata.description.isEmpty
                              ? '还没有简介。'
                              : metadata.description,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              _StatGrid(overview: overview),
              const SizedBox(height: 28),
              if (overview.volumeSummaries.isNotEmpty) ...[
                Text(
                  '卷摘要',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                for (final volume in overview.volumeSummaries) ...[
                  _VolumeRow(volume: volume),
                  const SizedBox(height: 8),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

final class _Cover extends StatelessWidget {
  const _Cover({
    required this.session,
    required this.assetService,
    required this.novelRoot,
    required this.coverPath,
  });

  final LibrarySession session;
  final LibraryAssetService assetService;
  final String novelRoot;
  final String? coverPath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 80,
        height: 120,
        child: coverPath == null
            ? Container(
                color: theme.colorScheme.surfaceContainer,
                child: Icon(
                  Icons.menu_book_outlined,
                  size: 30,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            : FutureBuilder<Uint8List?>(
                future: assetService.read(
                  session,
                  LogicalPath.parse('$novelRoot/$coverPath'),
                ),
                builder: (context, snapshot) {
                  final bytes = snapshot.data;
                  if (snapshot.connectionState != ConnectionState.done ||
                      bytes == null) {
                    return Container(
                      color: theme.colorScheme.surfaceContainer,
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        size: 24,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    );
                  }
                  return Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) => Container(
                      color: theme.colorScheme.surfaceContainer,
                      child: Icon(
                        Icons.broken_image_outlined,
                        size: 24,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

final class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.overview});

  final NovelOverview overview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget tile(String label, String value) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: tile('书稿字数', '${overview.totalCharacterCount}')),
            const SizedBox(width: 12),
            Expanded(child: tile('章节数', '${overview.chapterCount}')),
            const SizedBox(width: 12),
            Expanded(child: tile('卷数', '${overview.volumeCount}')),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: tile('今日净增', '${overview.todayCharacterCount}')),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: _GoalCard(
                today: overview.todayCharacterCount,
                goal: overview.dailyWordGoal,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

final class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.today, required this.goal});

  final int today;
  final int goal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (goal <= 0) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '未设置目标',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text('可在设置中配置每日字数目标', style: theme.textTheme.bodySmall),
          ],
        ),
      );
    }
    final progress = (today / goal).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '每日目标',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                '$today / $goal',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

final class _VolumeRow extends StatelessWidget {
  const _VolumeRow({required this.volume});

  final NovelVolumeSummary volume;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.folder_copy_outlined,
            size: 18,
            color: theme.colorScheme.secondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              volume.title,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '${volume.chapterCount} 章 · ${volume.characterCount} 字',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
