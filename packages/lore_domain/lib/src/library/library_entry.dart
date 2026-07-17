enum LibraryEntryType { directory, textFile, markdownFile, otherFile }

enum LibraryEntrySemanticKind { novel, body, volume, chapter }

final class LibraryEntry {
  const LibraryEntry({
    required this.name,
    required this.relativePath,
    required this.type,
    this.semanticKind,
    this.semanticId,
    this.novelId,
    this.semanticOrder,
  });

  final String name;
  final String relativePath;
  final LibraryEntryType type;
  final LibraryEntrySemanticKind? semanticKind;
  final String? semanticId;
  final String? novelId;
  final int? semanticOrder;

  bool get isDirectory => type == LibraryEntryType.directory;
}
