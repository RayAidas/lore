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
  });

  final ContentId id;
  final ContentNodeType type;
  final ContentId parentId;
  final String relativePath;
  final int order;
  final int? number;
  final ContentRole role;

  ContentNode copyWith({
    ContentId? parentId,
    String? relativePath,
    int? order,
    int? number,
    bool clearNumber = false,
    ContentRole? role,
  }) {
    return ContentNode(
      id: id,
      type: type,
      parentId: parentId ?? this.parentId,
      relativePath: relativePath ?? this.relativePath,
      order: order ?? this.order,
      number: clearNumber ? null : number ?? this.number,
      role: role ?? this.role,
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
