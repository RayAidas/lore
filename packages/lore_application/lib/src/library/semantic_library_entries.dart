import 'package:lore_domain/lore_domain.dart';

import 'novel_structure.dart';

Map<String, LibraryEntry> buildSemanticLibraryEntryIndex(
  Iterable<NovelSnapshot> novels,
) {
  final entries = <String, LibraryEntry>{};
  for (final novel in novels) {
    final novelEntry = semanticNovelEntry(novel);
    entries[novelEntry.relativePath] = novelEntry;
    final bodyEntry = semanticNovelBodyEntry(novel);
    entries[bodyEntry.relativePath] = bodyEntry;
    for (final node in novel.contentTree.nodes) {
      final contentEntry = semanticContentEntry(novel, node);
      entries[contentEntry.relativePath] = contentEntry;
    }
  }
  return entries;
}

LibraryEntry semanticNovelEntry(NovelSnapshot snapshot) => LibraryEntry(
  name: _basename(snapshot.rootPath),
  relativePath: snapshot.rootPath,
  type: LibraryEntryType.directory,
  semanticKind: LibraryEntrySemanticKind.novel,
  semanticId: snapshot.metadata.id.value,
  novelId: snapshot.metadata.id.value,
);

LibraryEntry semanticNovelBodyEntry(NovelSnapshot snapshot) {
  final relativePath = _join(
    snapshot.rootPath,
    snapshot.metadata.body.relativePath,
  );
  return LibraryEntry(
    name: _basename(snapshot.metadata.body.relativePath),
    relativePath: relativePath,
    type: LibraryEntryType.directory,
    semanticKind: LibraryEntrySemanticKind.body,
    semanticId: snapshot.metadata.body.id.value,
    novelId: snapshot.metadata.id.value,
  );
}

LibraryEntry semanticContentEntry(NovelSnapshot snapshot, ContentNode node) =>
    LibraryEntry(
      name: _basename(node.relativePath),
      relativePath: _join(snapshot.rootPath, node.relativePath),
      type: node.type == ContentNodeType.volume
          ? LibraryEntryType.directory
          : _libraryFileType(node.relativePath),
      semanticKind: node.type == ContentNodeType.volume
          ? LibraryEntrySemanticKind.volume
          : LibraryEntrySemanticKind.chapter,
      semanticId: node.id.value,
      novelId: snapshot.metadata.id.value,
      semanticOrder: node.order,
    );

String _basename(String path) => path.split('/').last;

String _join(String parent, String child) => '$parent/$child';

LibraryEntryType _libraryFileType(String path) {
  final name = _basename(path).toLowerCase();
  if (name.endsWith('.txt')) {
    return LibraryEntryType.textFile;
  }
  if (name.endsWith('.md')) {
    return LibraryEntryType.markdownFile;
  }
  return LibraryEntryType.otherFile;
}
