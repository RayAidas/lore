import 'dart:typed_data';

import 'package:lore_domain/lore_domain.dart';

import '../library/library_access.dart';

final class StorageCapabilities {
  const StorageCapabilities({
    required this.atomicReplace,
    required this.move,
    required this.rename,
    required this.watch,
    required this.caseSensitive,
  });

  final bool atomicReplace;
  final bool move;
  final bool rename;
  final bool watch;
  final bool caseSensitive;
}

enum StorageEntryType { file, directory }

final class StorageEntry {
  const StorageEntry({
    required this.path,
    required this.type,
    required this.size,
    required this.revision,
  });

  final LogicalPath path;
  final StorageEntryType type;
  final int? size;
  final String? revision;
}

enum StorageChangeType { created, modified, deleted, moved }

final class StorageChange {
  const StorageChange({
    required this.path,
    required this.type,
    this.destination,
  });

  final LogicalPath path;
  final StorageChangeType type;
  final LogicalPath? destination;
}

sealed class StorageReplaceResult {
  const StorageReplaceResult();
}

final class StorageReplaceSuccess extends StorageReplaceResult {
  const StorageReplaceSuccess(this.revision);

  final String revision;
}

final class StorageReplaceConflict extends StorageReplaceResult {
  const StorageReplaceConflict(this.currentRevision);

  final String? currentRevision;
}

abstract interface class LibraryStorageFactory {
  Future<LibraryStorageSession> open(LibraryAccess access);
}

abstract interface class LibraryStorageSession {
  StorageCapabilities get capabilities;

  Future<List<StorageEntry>> list(LogicalPath directory);

  Future<StorageEntry?> stat(LogicalPath path);

  Future<Uint8List> readBytes(LogicalPath path);

  Future<void> createDirectory(LogicalPath path);

  Future<void> createFile(LogicalPath path, Uint8List bytes);

  Future<StorageReplaceResult> replaceFile(
    LogicalPath path, {
    required String expectedRevision,
    required Uint8List bytes,
  });

  Future<void> move(LogicalPath source, LogicalPath target);

  Future<void> copy(LogicalPath source, LogicalPath target);

  Future<void> delete(LogicalPath path, {required bool recursive});

  Stream<StorageChange> watch();
}
