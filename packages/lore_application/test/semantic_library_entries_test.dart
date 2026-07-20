import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:test/test.dart';

void main() {
  test('builds one semantic entry index for novels and content nodes', () {
    final novel = NovelSnapshot(
      rootPath: '长夜行',
      metadata: NovelMetadata(
        schemaVersion: 2,
        revision: 0,
        id: const NovelId('11111111-1111-4111-8111-111111111111'),
        title: '长夜行',
        description: '',
        coverPath: null,
        body: const NovelBody(
          id: ContentId('22222222-2222-4222-8222-222222222222'),
          relativePath: '正文',
        ),
        chapterFormat: ChapterFormat.markdown,
        numberingMode: NumberingMode.continuous,
        createdAt: DateTime.utc(2026, 7, 21),
        updatedAt: DateTime.utc(2026, 7, 21),
      ),
      contentTree: ContentTree(
        schemaVersion: 2,
        novelId: const NovelId('11111111-1111-4111-8111-111111111111'),
        revision: 0,
        nodes: const [
          ContentNode(
            id: ContentId('33333333-3333-4333-8333-333333333333'),
            parentId: ContentId('22222222-2222-4222-8222-222222222222'),
            type: ContentNodeType.volume,
            relativePath: '正文/第一卷',
            order: 0,
            number: 1,
            role: ContentRole.normal,
          ),
          ContentNode(
            id: ContentId('44444444-4444-4444-8444-444444444444'),
            parentId: ContentId('33333333-3333-4333-8333-333333333333'),
            type: ContentNodeType.chapter,
            relativePath: '正文/第一卷/第一章.md',
            order: 1,
            number: 1,
            role: ContentRole.normal,
          ),
        ],
      ),
    );

    final entries = buildSemanticLibraryEntryIndex([novel]);

    expect(entries['长夜行']?.semanticKind, LibraryEntrySemanticKind.novel);
    expect(entries['长夜行/正文']?.semanticKind, LibraryEntrySemanticKind.body);
    expect(
      entries['长夜行/正文/第一卷']?.semanticKind,
      LibraryEntrySemanticKind.volume,
    );
    expect(entries['长夜行/正文/第一卷/第一章.md']?.type, LibraryEntryType.markdownFile);
  });
}
