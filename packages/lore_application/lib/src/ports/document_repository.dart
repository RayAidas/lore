import 'package:lore_domain/lore_domain.dart';

import '../library/library_access.dart';

sealed class DocumentSaveResult {
  const DocumentSaveResult();
}

final class DocumentSaveSuccess extends DocumentSaveResult {
  const DocumentSaveSuccess(this.snapshot);

  final DocumentSnapshot snapshot;
}

final class DocumentSaveConflict extends DocumentSaveResult {
  const DocumentSaveConflict(this.diskSnapshot);

  final DocumentSnapshot diskSnapshot;
}

enum DocumentChangeType { modified, deleted, moved, created }

final class DocumentChange {
  const DocumentChange({required this.relativePath, required this.type});

  final String relativePath;
  final DocumentChangeType type;
}

abstract interface class DocumentRepository {
  Future<DocumentSnapshot> readDocument(LibraryAccess access, DocumentRef ref);

  Future<DocumentSaveResult> saveDocument(
    LibraryAccess access, {
    required DocumentSnapshot original,
    required String text,
  });

  Stream<DocumentChange> watchDocuments(LibraryAccess access);
}
