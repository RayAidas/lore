import '../document/document.dart';

/// 触发历史快照的原因。
enum HistoryTrigger {
  /// 切换或关闭文档时自动留档。
  autoCheckpoint,

  /// 自上次快照后净变更量达到阈值（约 800 字）时自动留档。
  autoThreshold,

  /// 用户在历史面板主动创建，可带命名与备注，永久保留。
  manual,

  /// 恢复某历史版本前，为当前内容自动留底。
  restoreSafeguard,
}

/// 文档身份：章节用 [nodeId]（稳定，移动不断链）；小说目录外的普通文件
/// [nodeId] 为 null，退化为按 [relativePath] 关联——文件移动后历史会断链，
/// 属于已知限制。
///
/// 本类零依赖，只提供可读的 [logicalKey]；存储层据此生成目录安全名
/// （普通文件需对路径求哈希，因为路径含 `/` 不能直接作为目录名）。
final class DocumentIdentity {
  const DocumentIdentity({
    this.nodeId,
    required this.relativePath,
    required this.format,
  });

  /// 章节节点 ID；普通文件为 null。
  final String? nodeId;

  /// 相对书库根的标准化逻辑路径（`/` 分隔）。
  final String relativePath;

  final DocumentFormat format;

  /// manifest 中的逻辑标识：章节 `node:<id>`，普通文件 `path:<relativePath>`。
  String get logicalKey =>
      nodeId != null ? 'node:$nodeId' : 'path:$relativePath';

  /// 是否拥有稳定节点身份（章节）。
  bool get hasStableId => nodeId != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentIdentity &&
          other.nodeId == nodeId &&
          other.relativePath == relativePath &&
          other.format == format;

  @override
  int get hashCode => Object.hash(nodeId, relativePath, format);

  @override
  String toString() => logicalKey;
}

/// 单条历史快照的元信息。正文内容另行按 [id] 通过 HistoryRepository 读取。
final class HistorySnapshot {
  const HistorySnapshot({
    required this.id,
    required this.createdAt,
    required this.trigger,
    required this.contentHash,
    required this.characterCount,
    required this.isProtected,
    this.label,
    this.note,
  });

  /// 快照短 ID（同一文档内唯一）。
  final String id;

  final DateTime createdAt;
  final HistoryTrigger trigger;

  /// 正文 sha256，用于去重判定与 diff 标识。
  final String contentHash;

  /// 该版本正文字数（去空白 rune 计数）。
  final int characterCount;

  /// 手动创建的快照为 true，永久保留，不参与自动回收。
  final bool isProtected;

  /// 手动命名（如「交稿前」），自动快照为 null。
  final String? label;

  /// 手动备注，自动快照为 null。
  final String? note;

  /// 是否用户主动创建。
  bool get isManual => trigger == HistoryTrigger.manual;

  @override
  String toString() => 'HistorySnapshot($id, ${trigger.name}, $createdAt)';
}
