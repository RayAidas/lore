import 'package:lore_domain/lore_domain.dart';

import '../ports/clock.dart';
import '../ports/document_repository.dart';
import '../ports/novel_repository.dart';
import '../ports/writing_progress_repository.dart';
import 'library_bootstrap.dart';
import 'library_failure.dart';

final class NovelVolumeSummary {
  const NovelVolumeSummary({
    required this.nodeId,
    required this.title,
    required this.chapterCount,
    required this.characterCount,
  });

  final ContentId nodeId;
  final String title;
  final int chapterCount;
  final int characterCount;
}

/// 小说概览的只读投影，供概览页一次性展示。
final class NovelOverview {
  const NovelOverview({
    required this.metadata,
    required this.rootPath,
    required this.totalCharacterCount,
    required this.volumeCount,
    required this.chapterCount,
    required this.todayCharacterCount,
    required this.dailyWordGoal,
    required this.volumeSummaries,
  });

  final NovelMetadata metadata;

  /// 小说在书库内的相对路径，UI 据此解析封面等资源。
  final String rootPath;

  final int totalCharacterCount;
  final int volumeCount;
  final int chapterCount;
  final int todayCharacterCount;
  final int dailyWordGoal;
  final List<NovelVolumeSummary> volumeSummaries;
}

/// 计算小说概览。读取章节正文统计字数（仅长度，不解析），聚合卷摘要，
/// 并从 [WritingProgressRepository] 取今日字数。封面解析交给 UI 层。
final class NovelOverviewService {
  const NovelOverviewService({
    required this.novelRepository,
    required this.documentRepository,
    required this.clock,
    this.writingProgressRepository,
  });

  final NovelRepository novelRepository;
  final DocumentRepository documentRepository;
  final Clock clock;
  final WritingProgressRepository? writingProgressRepository;

  Future<NovelOverview> computeOverview(
    LibrarySession session, {
    required NovelId novelId,
    int dailyWordGoal = 0,
    DateTime? today,
  }) async {
    final snapshot = await novelRepository.loadNovel(
      session.access,
      novelId: novelId,
    );
    final tree = snapshot.contentTree;
    final chapterNodes = tree.nodes.where(
      (node) => node.type == ContentNodeType.chapter,
    );
    final volumeNodes = tree.nodes.where(
      (node) => node.type == ContentNodeType.volume,
    );

    var total = 0;
    final characterByNodeId = <ContentId, int>{};
    for (final node in chapterNodes) {
      final count = await _readChapterCount(session, snapshot.rootPath, node);
      characterByNodeId[node.id] = count;
      total += count;
    }

    final volumeSummaries = <NovelVolumeSummary>[];
    for (final volume in volumeNodes) {
      final children = tree
          .childrenOf(volume.id)
          .where((node) => node.type == ContentNodeType.chapter);
      final volumeCharacters = children.fold<int>(
        0,
        (sum, node) => sum + (characterByNodeId[node.id] ?? 0),
      );
      volumeSummaries.add(
        NovelVolumeSummary(
          nodeId: volume.id,
          title: _baseName(volume.relativePath),
          chapterCount: children.length,
          characterCount: volumeCharacters,
        ),
      );
    }

    final todayUtc = today ?? clock.nowUtc();
    final todayCount =
        await writingProgressRepository?.loadToday(novelId, todayUtc) ?? 0;

    return NovelOverview(
      metadata: snapshot.metadata,
      rootPath: snapshot.rootPath,
      totalCharacterCount: total,
      volumeCount: volumeNodes.length,
      chapterCount: chapterNodes.length,
      todayCharacterCount: todayCount,
      dailyWordGoal: dailyWordGoal,
      volumeSummaries: volumeSummaries,
    );
  }

  Future<int> _readChapterCount(
    LibrarySession session,
    String rootPath,
    ContentNode node,
  ) async {
    final isText = node.relativePath.toLowerCase().endsWith('.txt');
    final ref = DocumentRef(
      relativePath: _joinPath(rootPath, node.relativePath),
      format: isText ? DocumentFormat.text : DocumentFormat.markdown,
    );
    try {
      final snapshot = await documentRepository.readDocument(
        session.access,
        ref,
      );
      return _characterCount(snapshot.text);
    } on LibraryOperationException {
      return 0;
    }
  }

  /// application 层不依赖 path 包：书库内相对路径统一使用 `/`，用字符串拼接。
  String _joinPath(String root, String relative) {
    if (root.isEmpty) {
      return relative;
    }
    return root.endsWith('/') ? '$root$relative' : '$root/$relative';
  }

  String _baseName(String relativePath) {
    final index = relativePath.lastIndexOf('/');
    return index == -1 ? relativePath : relativePath.substring(index + 1);
  }

  int _characterCount(String text) {
    return text.replaceAll(RegExp(r'\s+'), '').runes.length;
  }
}
