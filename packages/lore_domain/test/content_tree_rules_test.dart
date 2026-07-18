import 'package:lore_domain/lore_domain.dart';
import 'package:test/test.dart';

void main() {
  const novelId = NovelId('novel');
  const bodyId = ContentId('body');

  ContentNode chapter(String id, int order) => ContentNode(
    id: ContentId(id),
    type: ContentNodeType.chapter,
    parentId: bodyId,
    relativePath: '正文/$id.md',
    order: order,
    number: order ~/ 1000,
    role: ContentRole.normal,
  );

  test('rejects duplicate identities and paths', () {
    final tree = ContentTree(
      schemaVersion: 2,
      novelId: novelId,
      revision: 0,
      nodes: [chapter('one', 1000), chapter('one', 2000)],
    );

    expect(
      () => ContentTreeRules.validate(tree, bodyId: bodyId),
      throwsFormatException,
    );
  });

  test('reorders only siblings and normalizes their order', () {
    final tree = ContentTree(
      schemaVersion: 2,
      novelId: novelId,
      revision: 0,
      nodes: [chapter('one', 1000), chapter('two', 2000)],
    );

    final nodes = ContentTreeRules.reorder(
      tree,
      nodeId: const ContentId('two'),
      newIndex: 0,
    );

    expect(nodes.firstWhere((node) => node.id.value == 'two').order, 1000);
    expect(nodes.firstWhere((node) => node.id.value == 'one').order, 2000);
  });
}
