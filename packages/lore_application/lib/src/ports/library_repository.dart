import 'package:lore_domain/lore_domain.dart';

import '../library/library_access.dart';
import '../library/library_inspection.dart';

abstract interface class LibraryRepository {
  Future<LibraryInspection> inspect(LibraryAccess access);

  Future<LibraryMetadata> initialize(LibraryAccess access);

  Future<List<LibraryEntry>> listChildren(
    LibraryAccess access, {
    String relativePath = '',
  });
}
