import '../library/novel.dart';
import 'content_id.dart';
import 'content_types.dart';

final class ContentNode {
  const ContentNode({
    required this.id,
    required this.type,
    required this.parentId,
    required this.relativePath,
    required this.order,
    required this.number,
    required this.role,
    this.characterCount,
  });

  final ContentId id;
  final ContentNodeType type;
  final ContentId parentId;
  final String relativePath;
  final int order;
  final int? number;
  final ContentRole role;

  /// 章节正文字数（不含标题行，去空白 rune 计数）。`null` 表示尚未计算（旧
  /// content.json 或新建未保存），由上层懒算回填；`0` 表示空章节。
  final int? characterCount;

  ContentNode copyWith({
    ContentId? parentId,
    String? relativePath,
    int? order,
    int? number,
    bool clearNumber = false,
    ContentRole? role,
    int? characterCount,
    bool clearCharacterCount = false,
  }) {
    return ContentNode(
      id: id,
      type: type,
      parentId: parentId ?? this.parentId,
      relativePath: relativePath ?? this.relativePath,
      order: order ?? this.order,
      number: clearNumber ? null : number ?? this.number,
      role: role ?? this.role,
      characterCount: clearCharacterCount
          ? null
          : characterCount ?? this.characterCount,
    );
  }
}

final class ContentTree {
  const ContentTree({
    required this.schemaVersion,
    required this.novelId,
    required this.revision,
    required this.nodes,
  });

  final int schemaVersion;
  final NovelId novelId;
  final int revision;
  final List<ContentNode> nodes;

  List<ContentNode> childrenOf(ContentId parentId) {
    final children = nodes
        .where((node) => node.parentId == parentId)
        .toList(growable: false);
    children.sort((left, right) => left.order.compareTo(right.order));
    return children;
  }

  ContentNode? nodeById(ContentId id) {
    for (final node in nodes) {
      if (node.id == id) {
        return node;
      }
    }
    return null;
  }
}
