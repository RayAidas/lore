import 'dart:io';
import 'dart:typed_data';

import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_storage/lore_storage.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late LocalDirectoryStorageSession storage;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lore-storage-session-');
    storage =
        await const LocalDirectoryStorageFactory().open(
              LibraryAccess(
                token: root.path,
                displayPath: root.path,
                isPending: false,
              ),
            )
            as LocalDirectoryStorageSession;
  });

  tearDown(() => root.delete(recursive: true));

  test('creates, reads and replaces with revision checks', () async {
    final path = LogicalPath.parse('chapter.md');
    await storage.createFile(path, Uint8List.fromList('first'.codeUnits));
    final original = await storage.stat(path);

    final result = await storage.replaceFile(
      path,
      expectedRevision: original!.revision!,
      bytes: Uint8List.fromList('second'.codeUnits),
    );

    expect(result, isA<StorageReplaceSuccess>());
    expect(String.fromCharCodes(await storage.readBytes(path)), 'second');
    expect(
      await storage.replaceFile(
        path,
        expectedRevision: original.revision!,
        bytes: Uint8List(0),
      ),
      isA<StorageReplaceConflict>(),
    );
  });

  test('copies directory trees and rejects traversal paths', () async {
    await storage.createDirectory(LogicalPath.parse('source'));
    await storage.createFile(
      LogicalPath.parse('source/chapter.txt'),
      Uint8List.fromList([1, 2, 3]),
    );

    await storage.copy(LogicalPath.parse('source'), LogicalPath.parse('copy'));

    expect(
      await storage.stat(LogicalPath.parse('copy/chapter.txt')),
      isNotNull,
    );
    expect(() => LogicalPath.parse('../outside'), throwsFormatException);
  });
}
