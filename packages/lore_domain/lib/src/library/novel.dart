import '../content/content_id.dart';
import '../content/content_types.dart';

final class NovelId {
  const NovelId(this.value);

  final String value;

  @override
  bool operator ==(Object other) {
    return identical(this, other) || other is NovelId && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

final class NovelRegistration {
  const NovelRegistration({required this.id, required this.relativePath});

  final NovelId id;
  final String relativePath;
}

final class NovelBody {
  const NovelBody({required this.id, required this.relativePath});

  final ContentId id;
  final String relativePath;
}

final class NovelMetadata {
  const NovelMetadata({
    required this.schemaVersion,
    required this.id,
    required this.title,
    required this.description,
    required this.coverPath,
    required this.body,
    required this.chapterFormat,
    required this.numberingMode,
    required this.createdAt,
    required this.updatedAt,
  });

  final int schemaVersion;
  final NovelId id;
  final String title;
  final String description;
  final String? coverPath;
  final NovelBody body;
  final ChapterFormat chapterFormat;
  final NumberingMode numberingMode;
  final DateTime createdAt;
  final DateTime updatedAt;
}
