enum LibraryEntryType { directory, textFile, markdownFile, otherFile }

final class LibraryEntry {
  const LibraryEntry({
    required this.name,
    required this.relativePath,
    required this.type,
  });

  final String name;
  final String relativePath;
  final LibraryEntryType type;

  bool get isDirectory => type == LibraryEntryType.directory;
}
