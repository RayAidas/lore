import 'package:lore_domain/lore_domain.dart';

import 'novel_structure.dart';

/// 一次删除操作的结果。
///
/// [trashToken] 是恢复时定位回收站条目的钥匙；[removedNodeIds] 记录被
/// 移除的内容节点（删卷时含其全部章节），便于上层清理标签页等派生状态；
/// [pathChanges] 描述原路径到回收站路径的映射。
final class DeletionResult {
  const DeletionResult({
    this.snapshot,
    required this.trashToken,
    required this.removedNodeIds,
    required this.pathChanges,
  });

  final NovelSnapshot? snapshot;
  final String trashToken;
  final List<ContentId> removedNodeIds;
  final List<PathChange> pathChanges;
}
