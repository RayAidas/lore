import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:path/path.dart' as p;

/// 当前章节在全书阅读顺序中的导航上下文。
///
/// 供编辑器状态栏章节导航条使用：`第 index+1 / total 章`、上一章 / 下一章
/// 跳转路径、以及「新建下一章」所需的卷归属。`volumeId` 为 null 表示当前章
/// 是正文根级章节（直接挂在 body 下，非任何卷）。
///
/// `previousPath` / `nextPath` 为 session 根相对路径（与
/// [OpenDocument.relativePath] 口径一致，可直接交给
/// [WorkspaceController.openPath]），由 `p.join(rootPath, node.relativePath)`
/// 还原——这隐式依赖 [ContentNode.relativePath] 为 novel 根相对（由 store 层
/// `p.relative` 归一化），若未来改为 session 根相对会双拼前缀。
final class ChapterNavigation {
  const ChapterNavigation({
    required this.novelId,
    required this.volumeId,
    required this.index,
    required this.total,
    required this.previousPath,
    required this.nextPath,
  });

  final NovelId novelId;

  /// 当前章所在卷；正文根级章节为 null。新建下一章时沿用同一卷。
  final ContentId? volumeId;

  /// 当前章在全书阅读序列中的位置（0-based）。
  final int index;

  /// 全书章节数（阅读序列长度）。
  final int total;

  /// 上一章的相对路径（session 根相对）；当前章为首章时为 null。
  final String? previousPath;

  /// 下一章的相对路径（session 根相对）；当前章为末章时为 null。
  final String? nextPath;

  bool get hasPrevious => previousPath != null;
  bool get hasNext => nextPath != null;
}

/// 全书章节阅读顺序：正文根级章节（parentId == body.id）在前，其后各卷按
/// `order` 升序、卷内章节按 `childrenOf`（已按 `order` 排序）串联。
///
/// 不依赖 [ContentTree.nodes] 的底层存储顺序，结果稳定可预测——卷与根级
/// 章节的相对位置在存储层无显式约束，这里以「根级在前、卷在后」固化。
List<ContentNode> chaptersInReadingOrder(NovelSnapshot novel) {
  final tree = novel.contentTree;
  final bodyId = novel.metadata.body.id;
  final chapters = <ContentNode>[];

  for (final node in tree.childrenOf(bodyId)) {
    if (node.type == ContentNodeType.chapter) {
      chapters.add(node);
    }
  }

  final volumes = tree.nodes
      .where((node) => node.type == ContentNodeType.volume)
      .toList()
    ..sort((a, b) => a.order.compareTo(b.order));
  for (final volume in volumes) {
    for (final node in tree.childrenOf(volume.id)) {
      if (node.type == ContentNodeType.chapter) {
        chapters.add(node);
      }
    }
  }

  return chapters;
}

/// 由小说快照与当前章节节点计算导航上下文。
///
/// `node` 不在该小说章节序列中（如属于其他小说、或类型非章节）时返回 null。
/// 路径口径为 session 根相对（与 [OpenDocument.relativePath] 一致），可直接
/// 交给 [WorkspaceController.openPath]。
ChapterNavigation? computeChapterNavigation(
  NovelSnapshot novel,
  ContentNode node,
) {
  final ordered = chaptersInReadingOrder(novel);
  final index = ordered.indexWhere((candidate) => candidate.id == node.id);
  if (index < 0) {
    return null;
  }
  final bodyId = novel.metadata.body.id;
  final volumeId = node.parentId == bodyId ? null : node.parentId;

  String pathOf(ContentNode chapter) =>
      p.join(novel.rootPath, chapter.relativePath);

  return ChapterNavigation(
    novelId: novel.metadata.id,
    volumeId: volumeId,
    index: index,
    total: ordered.length,
    previousPath: index > 0 ? pathOf(ordered[index - 1]) : null,
    nextPath:
        index < ordered.length - 1 ? pathOf(ordered[index + 1]) : null,
  );
}
