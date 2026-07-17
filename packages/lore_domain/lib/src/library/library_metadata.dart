import 'library_id.dart';

final class LibraryMetadata {
  const LibraryMetadata({
    required this.schemaVersion,
    required this.id,
    required this.createdAt,
    required this.updatedAt,
  });

  final int schemaVersion;
  final LibraryId id;
  final DateTime createdAt;
  final DateTime updatedAt;
}
