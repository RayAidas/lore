import 'dart:typed_data';

import 'package:lore_domain/lore_domain.dart';

import '../ports/library_storage.dart';
import 'library_bootstrap.dart';

final class LibraryAssetService {
  const LibraryAssetService(this.storageFactory);

  final LibraryStorageFactory storageFactory;

  Future<Uint8List?> read(LibrarySession session, LogicalPath path) async {
    final storage = await storageFactory.open(session.access);
    final entry = await storage.stat(path);
    if (entry?.type != StorageEntryType.file) {
      return null;
    }
    return storage.readBytes(path);
  }

  Future<Uint8List?> readRelative(
    LibrarySession session, {
    required String documentPath,
    required String relativeReference,
  }) async {
    final document = LogicalPath.parse(documentPath);
    final segments = <String>[
      ...?document.parent?.value
          .split('/')
          .where((segment) => segment.isNotEmpty),
    ];
    for (final segment in relativeReference.replaceAll(r'\', '/').split('/')) {
      if (segment.isEmpty || segment == '.') {
        continue;
      }
      if (segment == '..') {
        if (segments.isEmpty) {
          return null;
        }
        segments.removeLast();
        continue;
      }
      segments.add(segment);
    }
    if (segments.isEmpty) {
      return null;
    }
    try {
      return read(session, LogicalPath.parse(segments.join('/')));
    } on FormatException {
      return null;
    }
  }
}
