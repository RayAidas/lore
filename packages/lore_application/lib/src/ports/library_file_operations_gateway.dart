import 'dart:typed_data';

import '../library/library_access.dart';

abstract interface class LibraryFileOperationsGateway {
  Future<void> rename(
    LibraryAccess access, {
    required String sourcePath,
    required String targetPath,
  });

  Future<bool> replaceDocument(
    LibraryAccess access, {
    required String relativePath,
    required String expectedRevision,
    required Uint8List bytes,
  });
}
