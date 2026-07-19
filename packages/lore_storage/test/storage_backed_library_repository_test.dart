import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_storage/lore_storage.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late StorageBackedLibraryRepository repository;
  late LibraryAccess access;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lore-portable-repository-');
    access = LibraryAccess(
      token: root.path,
      displayPath: root.path,
      isPending: false,
    );
    repository = StorageBackedLibraryRepository(
      storageFactory: LocalDirectoryStorageFactory(),
      idGenerator: _SequentialIdGenerator(),
      clock: const _FixedClock(),
    );
  });

  tearDown(() => root.delete(recursive: true));

  test('createChapter seeds the chapter title as the first line', () async {
    await repository.initialize(access);

    // TXT：首行 `第1章` + 换行。
    final txtNovel = await repository.createNovel(
      access,
      title: 'TXT 小说',
      chapterFormat: ChapterFormat.text,
    );
    final txtChapter = await repository.createChapter(
      access,
      novelId: txtNovel.snapshot.metadata.id,
    );
    final txtDoc = await repository.readDocument(
      access,
      DocumentRef(
        relativePath: txtChapter.entry!.relativePath,
        format: DocumentFormat.text,
      ),
    );
    expect(txtDoc.text, '第1章\n');
    expect(txtChapter.entry!.name, '第1章.txt');

    // Markdown：首行 `# 第1章` + 换行（预览即标题）。
    final mdNovel = await repository.createNovel(
      access,
      title: 'MD 小说',
      chapterFormat: ChapterFormat.markdown,
    );
    final mdChapter = await repository.createChapter(
      access,
      novelId: mdNovel.snapshot.metadata.id,
    );
    final mdDoc = await repository.readDocument(
      access,
      DocumentRef(
        relativePath: mdChapter.entry!.relativePath,
        format: DocumentFormat.markdown,
      ),
    );
    expect(mdDoc.text, '# 第1章\n');

    // 连续编号：第二个 TXT 章节应为第 2 章。
    final secondChapter = await repository.createChapter(
      access,
      novelId: txtNovel.snapshot.metadata.id,
    );
    final secondDoc = await repository.readDocument(
      access,
      DocumentRef(
        relativePath: secondChapter.entry!.relativePath,
        format: DocumentFormat.text,
      ),
    );
    expect(secondDoc.text, '第2章\n');
    expect(secondChapter.entry!.name, '第2章.txt');
  });

  test('completes the portable novel writing and trash loop', () async {
    final library = await repository.initialize(access);
    final novelMutation = await repository.createNovel(access, title: '长夜行');
    final chapterMutation = await repository.createChapter(
      access,
      novelId: novelMutation.snapshot.metadata.id,
    );
    final chapter = chapterMutation.snapshot.contentTree.nodes.single;
    final documentRef = DocumentRef(
      relativePath: chapterMutation.entry!.relativePath,
      format: DocumentFormat.markdown,
    );
    final original = await repository.readDocument(access, documentRef);
    final saved = await repository.saveDocument(
      access,
      original: original,
      text: '第一章',
    );
    final deletion = await repository.deleteNode(
      access,
      novelId: novelMutation.snapshot.metadata.id,
      nodeId: chapter.id,
    );

    expect(library.schemaVersion, 2);
    expect(saved, isA<DocumentSaveSuccess>());
    expect(await repository.listItems(access), hasLength(1));

    await repository.restore(access, trashToken: deletion.trashToken);
    final restored = await repository.loadNovel(
      access,
      novelId: novelMutation.snapshot.metadata.id,
    );
    expect(restored.contentTree.nodeById(chapter.id), isNotNull);
    expect((await repository.readDocument(access, documentRef)).text, '第一章');
  });

  test('migrates v1 novel manifests through the storage abstraction', () async {
    final metadataRoot = Directory('${root.path}/.lore');
    final novelMetadataRoot = Directory('${root.path}/长夜行/.lore');
    await metadataRoot.create(recursive: true);
    await novelMetadataRoot.create(recursive: true);
    await Directory('${root.path}/长夜行/正文').create(recursive: true);
    await File('${root.path}/长夜行/正文/第一章.md').writeAsString('正文');
    await _writeJson(File('${metadataRoot.path}/library.json'), {
      'schemaVersion': 1,
      'libraryId': '11111111-1111-4111-8111-111111111111',
      'createdAt': '2026-07-17T00:00:00.000Z',
      'updatedAt': '2026-07-17T00:00:00.000Z',
      'novels': [
        {'id': '22222222-2222-4222-8222-222222222222', 'path': '长夜行'},
      ],
      'templates': <Object?>[],
    });
    await _writeJson(File('${novelMetadataRoot.path}/novel.json'), {
      'schemaVersion': 1,
      'novelId': '22222222-2222-4222-8222-222222222222',
      'title': '长夜行',
      'description': '',
      'cover': null,
      'body': {'id': '33333333-3333-4333-8333-333333333333', 'path': r'正文'},
      'chapterFormat': 'markdown',
      'numberingMode': 'continuous',
      'createdAt': '2026-07-17T00:00:00.000Z',
      'updatedAt': '2026-07-17T00:00:00.000Z',
    });
    await _writeJson(File('${novelMetadataRoot.path}/content.json'), {
      'schemaVersion': 1,
      'novelId': '22222222-2222-4222-8222-222222222222',
      'revision': 4,
      'nodes': [
        {
          'id': '44444444-4444-4444-8444-444444444444',
          'type': 'chapter',
          'parentId': '33333333-3333-4333-8333-333333333333',
          'path': r'正文\第一章.md',
          'order': 1000,
          'number': 1,
          'role': 'normal',
        },
      ],
    });

    final inspection = await repository.inspect(access);
    final novel = await repository.loadNovel(
      access,
      novelId: const NovelId('22222222-2222-4222-8222-222222222222'),
    );
    final migratedLibrary =
        jsonDecode(
              await File('${metadataRoot.path}/library.json').readAsString(),
            )
            as Map<String, Object?>;
    final migratedNovel =
        jsonDecode(
              await File('${novelMetadataRoot.path}/novel.json').readAsString(),
            )
            as Map<String, Object?>;

    expect(inspection, isA<LibraryInspectionReady>());
    expect(migratedLibrary['schemaVersion'], 2);
    expect(migratedLibrary['revision'], 0);
    expect(migratedNovel['schemaVersion'], 2);
    expect(migratedNovel['revision'], 0);
    expect(novel.contentTree.nodes.single.relativePath, '正文/第一章.md');
    expect(
      Directory('${root.path}/.lore/recovery/migrations').listSync(),
      isNotEmpty,
    );
  });

  test(
    'preserves semantic order and increments reconciliation revision',
    () async {
      final factory = _InterceptingStorageFactory(
        LocalDirectoryStorageFactory(),
        reverseLists: true,
      );
      repository = StorageBackedLibraryRepository(
        storageFactory: factory,
        idGenerator: _SequentialIdGenerator(),
        clock: const _FixedClock(),
      );
      await repository.initialize(access);
      final novel = await repository.createNovel(access, title: '长夜行');
      final first = await repository.createChapter(
        access,
        novelId: novel.snapshot.metadata.id,
      );
      final second = await repository.createChapter(
        access,
        novelId: novel.snapshot.metadata.id,
      );
      final reordered = await repository.reorderNode(
        access,
        novelId: novel.snapshot.metadata.id,
        nodeId: second.snapshot.contentTree.nodes.last.id,
        newIndex: 0,
      );
      final expectedOrders = {
        for (final node in reordered.snapshot.contentTree.nodes)
          node.id: node.order,
      };

      final unchanged = await repository.reconcile(
        access,
        novelId: novel.snapshot.metadata.id,
      );
      await File('${root.path}/长夜行/正文/外部章节.md').writeAsString('外部');
      final changed = await repository.reconcile(
        access,
        novelId: novel.snapshot.metadata.id,
      );

      expect(
        unchanged.snapshot.contentTree.revision,
        reordered.snapshot.contentTree.revision,
      );
      for (final node in first.snapshot.contentTree.nodes) {
        expect(expectedOrders, contains(node.id));
      }
      for (final entry in expectedOrders.entries) {
        expect(
          changed.snapshot.contentTree.nodeById(entry.key)?.order,
          entry.value,
        );
      }
      expect(
        changed.snapshot.contentTree.revision,
        reordered.snapshot.contentTree.revision + 1,
      );
    },
  );

  test('keeps interrupted deletes restorable with stable node ids', () async {
    final factory = _InterceptingStorageFactory(LocalDirectoryStorageFactory());
    repository = StorageBackedLibraryRepository(
      storageFactory: factory,
      idGenerator: _SequentialIdGenerator(),
      clock: const _FixedClock(),
    );
    await repository.initialize(access);
    final novel = await repository.createNovel(access, title: '长夜行');
    final chapterMutation = await repository.createChapter(
      access,
      novelId: novel.snapshot.metadata.id,
    );
    final chapter = chapterMutation.snapshot.contentTree.nodes.single;
    factory.failNextReplacePath = '长夜行/.lore/content.json';

    await expectLater(
      repository.deleteNode(
        access,
        novelId: novel.snapshot.metadata.id,
        nodeId: chapter.id,
      ),
      throwsA(isA<LibraryOperationException>()),
    );

    final trash = await repository.listItems(access);
    expect(trash, hasLength(1));
    await repository.restore(access, trashToken: trash.single.token);
    final restored = await repository.loadNovel(
      access,
      novelId: novel.snapshot.metadata.id,
    );
    expect(restored.contentTree.nodes, hasLength(1));
    expect(restored.contentTree.nodes.single.id, chapter.id);
  });

  test('renames uppercase extensions without appending a duplicate', () async {
    await repository.initialize(access);
    final created = await repository.createDocument(
      access,
      parentPath: '',
      name: '章节.MD',
      format: DocumentFormat.markdown,
    );

    final renamed = await repository.renameEntry(
      access,
      relativePath: created.relativePath,
      newName: '新名.md',
    );

    expect(renamed.relativePath, '新名.md');
  });
}

Future<void> _writeJson(File file, Map<String, Object?> value) {
  return file.writeAsString('${jsonEncode(value)}\n');
}

final class _SequentialIdGenerator implements IdGenerator {
  var _next = 0;

  @override
  String generate() {
    _next += 1;
    return '00000000-0000-4000-8000-${_next.toString().padLeft(12, '0')}';
  }
}

final class _FixedClock implements Clock {
  const _FixedClock();

  @override
  DateTime nowUtc() => DateTime.utc(2026, 7, 18);
}

final class _InterceptingStorageFactory implements LibraryStorageFactory {
  _InterceptingStorageFactory(this.delegate, {this.reverseLists = false});

  final LibraryStorageFactory delegate;
  final bool reverseLists;
  String? failNextReplacePath;

  @override
  Future<LibraryStorageSession> open(LibraryAccess access) async {
    return _InterceptingStorageSession(
      await delegate.open(access),
      owner: this,
    );
  }
}

final class _InterceptingStorageSession implements LibraryStorageSession {
  const _InterceptingStorageSession(this.delegate, {required this.owner});

  final LibraryStorageSession delegate;
  final _InterceptingStorageFactory owner;

  @override
  StorageCapabilities get capabilities => delegate.capabilities;

  @override
  Future<List<StorageEntry>> list(LogicalPath directory) async {
    final entries = await delegate.list(directory);
    return owner.reverseLists ? entries.reversed.toList() : entries;
  }

  @override
  Future<StorageEntry?> stat(LogicalPath path) => delegate.stat(path);

  @override
  Future<Uint8List> readBytes(LogicalPath path) => delegate.readBytes(path);

  @override
  Future<void> createDirectory(LogicalPath path) =>
      delegate.createDirectory(path);

  @override
  Future<void> createFile(LogicalPath path, Uint8List bytes) =>
      delegate.createFile(path, bytes);

  @override
  Future<StorageReplaceResult> replaceFile(
    LogicalPath path, {
    required String expectedRevision,
    required Uint8List bytes,
  }) async {
    if (owner.failNextReplacePath == path.value) {
      owner.failNextReplacePath = null;
      return StorageReplaceConflict((await delegate.stat(path))?.revision);
    }
    return delegate.replaceFile(
      path,
      expectedRevision: expectedRevision,
      bytes: bytes,
    );
  }

  @override
  Future<void> move(LogicalPath source, LogicalPath target) =>
      delegate.move(source, target);

  @override
  Future<void> copy(LogicalPath source, LogicalPath target) =>
      delegate.copy(source, target);

  @override
  Future<void> delete(LogicalPath path, {required bool recursive}) =>
      delegate.delete(path, recursive: recursive);

  @override
  Stream<StorageChange> watch() => delegate.watch();
}
