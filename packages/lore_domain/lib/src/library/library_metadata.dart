import 'library_id.dart';
import 'novel.dart';

final class LibraryMetadata {
  const LibraryMetadata({
    required this.schemaVersion,
    this.revision = 0,
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.novels = const [],
  });

  final int schemaVersion;
  final int revision;
  final LibraryId id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<NovelRegistration> novels;
}
