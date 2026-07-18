import 'content_id.dart';
import 'content_tree.dart';
import 'content_types.dart';

abstract final class ContentTreeRules {
  static void validate(ContentTree tree, {required ContentId bodyId}) {
    final ids = <ContentId>{};
    final paths = <String>{};
    for (final node in tree.nodes) {
      if (!ids.add(node.id)) {
        throw const FormatException('Content node ids must be unique.');
      }
      if (!paths.add(node.relativePath)) {
        throw const FormatException('Content node paths must be unique.');
      }
      if (node.order <= 0) {
        throw const FormatException('Content order must be positive.');
      }
    }
    final nodesById = {for (final node in tree.nodes) node.id: node};
    for (final node in tree.nodes) {
      if (node.parentId == bodyId) {
        continue;
      }
      final parent = nodesById[node.parentId];
      if (node.type != ContentNodeType.chapter ||
          parent?.type != ContentNodeType.volume) {
        throw const FormatException('Content parent relationship is invalid.');
      }
    }
  }

  static List<ContentNode> reorder(
    ContentTree tree, {
    required ContentId nodeId,
    required int newIndex,
    int orderStep = 1000,
  }) {
    final node = tree.nodeById(nodeId);
    if (node == null) {
      throw const FormatException('Content node does not exist.');
    }
    final siblings = tree.childrenOf(node.parentId).toList();
    final oldIndex = siblings.indexWhere((candidate) => candidate.id == nodeId);
    if (oldIndex < 0 || newIndex < 0 || newIndex >= siblings.length) {
      throw const FormatException('Content reorder index is invalid.');
    }
    siblings.insert(newIndex, siblings.removeAt(oldIndex));
    final orders = <ContentId, int>{
      for (var index = 0; index < siblings.length; index += 1)
        siblings[index].id: (index + 1) * orderStep,
    };
    return tree.nodes
        .map(
          (candidate) => orders[candidate.id] == null
              ? candidate
              : candidate.copyWith(order: orders[candidate.id]),
        )
        .toList(growable: false);
  }
}
