import 'dart:convert';
import 'dart:io';

import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_storage/lore_storage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late StorageBackedLibraryRepository repository;
  late LibraryAccess access;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lore-library-test-');
    access = LibraryAccess(
      token: root.path,
      displayPath: root.path,
      isPending: false,
    );
    repository = StorageBackedLibraryRepository(
      storageFactory: LocalDirectoryStorageFactory(),
      idGenerator: _SequenceIdGenerator(),
      clock: _FixedClock(DateTime.utc(2026, 7, 17, 8, 30)),
    );
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('initializes metadata without modifying existing files', () async {
    final existing = File(p.join(root.path, '灵感.txt'));
    await existing.writeAsString('保留内容');

    final metadata = await repository.initialize(access);

    expect(metadata.schemaVersion, 2);
    expect(metadata.revision, 0);
    expect(metadata.id.value, '11111111-1111-4111-8111-111111111111');
    expect(await existing.readAsString(), '保留内容');
    final manifest = File(p.join(root.path, '.lore', 'library.json'));
    expect(await manifest.exists(), isTrue);
    final json =
        jsonDecode(await manifest.readAsString()) as Map<String, Object?>;
    expect(json['schemaVersion'], 2);
    expect(json['revision'], 0);
    expect(json['novels'], isEmpty);
    expect(json['templates'], isEmpty);
    expect(
      await Directory(p.join(root.path, '.lore'))
          .list()
          .where((entity) => p.basename(entity.path).contains('.tmp-'))
          .isEmpty,
      isTrue,
    );
  });

  test('opens a valid initialized library', () async {
    final initialized = await repository.initialize(access);

    final inspection = await repository.inspect(access);

    expect(inspection, isA<LibraryInspectionReady>());
    final ready = inspection as LibraryInspectionReady;
    expect(ready.metadata.id, initialized.id);
  });

  test('migrates a v1 library to v2 without touching content files', () async {
    final metadataDirectory = Directory(p.join(root.path, '.lore'));
    await metadataDirectory.create();
    final content = File(p.join(root.path, '灵感.txt'));
    await content.writeAsString('必须保留');
    final manifest = File(p.join(metadataDirectory.path, 'library.json'));
    await manifest.writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'libraryId': '11111111-1111-4111-8111-111111111111',
        'createdAt': '2026-07-17T08:30:00.000Z',
        'updatedAt': '2026-07-17T08:30:00.000Z',
        'novels': <Object?>[],
        'templates': <Object?>[],
      }),
    );

    final inspection = await repository.inspect(access);

    expect(inspection, isA<LibraryInspectionReady>());
    final migrated = jsonDecode(await manifest.readAsString());
    expect(migrated['schemaVersion'], 2);
    expect(migrated['revision'], 0);
    expect(await content.readAsString(), '必须保留');
    final backups = Directory(
      p.join(root.path, '.lore', 'recovery', 'migrations'),
    );
    expect(await backups.exists(), isTrue);
    expect(await backups.list().isEmpty, isFalse);
  });

  test('never overwrites corrupt metadata', () async {
    final metadataDirectory = Directory(p.join(root.path, '.lore'));
    await metadataDirectory.create();
    final manifest = File(p.join(metadataDirectory.path, 'library.json'));
    await manifest.writeAsString('{broken');

    await expectLater(
      repository.initialize(access),
      throwsA(
        isA<LibraryOperationException>().having(
          (error) => error.failure.code,
          'code',
          LibraryFailureCode.metadataCorrupt,
        ),
      ),
    );
    expect(await manifest.readAsString(), '{broken');
  });

  test('never overwrites metadata created during initialization', () async {
    final manifest = File(p.join(root.path, '.lore', 'library.json'));
    const externalContent = 'externally created metadata';
    repository = StorageBackedLibraryRepository(
      storageFactory: LocalDirectoryStorageFactory(),
      idGenerator: _CreatingIdGenerator(manifest, externalContent),
      clock: _FixedClock(DateTime.utc(2026, 7, 17, 8, 30)),
    );

    await expectLater(
      repository.initialize(access),
      throwsA(
        isA<LibraryOperationException>().having(
          (error) => error.failure.code,
          'code',
          LibraryFailureCode.metadataCorrupt,
        ),
      ),
    );

    expect(await manifest.readAsString(), externalContent);
  });

  test('reports unsupported schema without rewriting it', () async {
    final metadataDirectory = Directory(p.join(root.path, '.lore'));
    await metadataDirectory.create();
    final manifest = File(p.join(metadataDirectory.path, 'library.json'));
    await manifest.writeAsString(
      jsonEncode({
        'schemaVersion': 99,
        'libraryId': '11111111-1111-4111-8111-111111111111',
        'createdAt': '2026-07-17T08:30:00.000Z',
        'updatedAt': '2026-07-17T08:30:00.000Z',
        'novels': <Object?>[],
        'templates': <Object?>[],
      }),
    );

    final inspection = await repository.inspect(access);

    expect(inspection, isA<LibraryInspectionFailure>());
    expect(
      (inspection as LibraryInspectionFailure).failure.code,
      LibraryFailureCode.unsupportedSchema,
    );
  });

  test('rejects a metadata directory symbolic link', () async {
    final externalDirectory = await Directory.systemTemp.createTemp(
      'lore-external-metadata-',
    );
    try {
      await File(p.join(externalDirectory.path, 'library.json')).writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'libraryId': '11111111-1111-4111-8111-111111111111',
          'createdAt': '2026-07-17T08:30:00.000Z',
          'updatedAt': '2026-07-17T08:30:00.000Z',
          'novels': <Object?>[],
          'templates': <Object?>[],
        }),
      );
      await Link(p.join(root.path, '.lore')).create(externalDirectory.path);

      final inspection = await repository.inspect(access);

      expect(inspection, isA<LibraryInspectionFailure>());
      expect(
        (inspection as LibraryInspectionFailure).failure.code,
        LibraryFailureCode.invalidLocation,
      );
    } finally {
      await externalDirectory.delete(recursive: true);
    }
  });

  test('rejects a manifest symbolic link', () async {
    final metadataDirectory = Directory(p.join(root.path, '.lore'));
    await metadataDirectory.create();
    final externalDirectory = await Directory.systemTemp.createTemp(
      'lore-external-manifest-',
    );
    try {
      final externalManifest = File(
        p.join(externalDirectory.path, 'library.json'),
      );
      await externalManifest.writeAsString('{}');
      await Link(
        p.join(metadataDirectory.path, 'library.json'),
      ).create(externalManifest.path);

      final inspection = await repository.inspect(access);

      expect(inspection, isA<LibraryInspectionFailure>());
      expect(
        (inspection as LibraryInspectionFailure).failure.code,
        LibraryFailureCode.invalidLocation,
      );
    } finally {
      await externalDirectory.delete(recursive: true);
    }
  });

  test('lists directories first and hides dotfiles and links', () async {
    await Directory(p.join(root.path, '资料')).create();
    await File(p.join(root.path, '章节.md')).writeAsString('');
    await File(p.join(root.path, '随笔.txt')).writeAsString('');
    await File(p.join(root.path, '封面.png')).writeAsBytes(const []);
    await File(p.join(root.path, '.DS_Store')).writeAsString('');
    await Link(p.join(root.path, '外部链接')).create(root.parent.path);

    final entries = await repository.listChildren(access);

    expect(entries.map((entry) => entry.name), [
      '资料',
      '封面.png',
      '章节.md',
      '随笔.txt',
    ]);
    expect(entries.first.type, LibraryEntryType.directory);
    expect(entries[2].type, LibraryEntryType.markdownFile);
    expect(entries[3].type, LibraryEntryType.textFile);
  });

  test('rejects paths that escape the library root', () async {
    await expectLater(
      repository.listChildren(access, relativePath: '../'),
      throwsA(
        isA<LibraryOperationException>().having(
          (error) => error.failure.code,
          'code',
          LibraryFailureCode.invalidLocation,
        ),
      ),
    );
  });

  test('rejects paths that escape through a nested symbolic link', () async {
    final externalDirectory = await Directory.systemTemp.createTemp(
      'lore-external-directory-',
    );
    try {
      await Directory(p.join(externalDirectory.path, '子目录')).create();
      await Link(p.join(root.path, '外部链接')).create(externalDirectory.path);

      await expectLater(
        repository.listChildren(access, relativePath: p.join('外部链接', '子目录')),
        throwsA(
          isA<LibraryOperationException>().having(
            (error) => error.failure.code,
            'code',
            LibraryFailureCode.invalidLocation,
          ),
        ),
      );
    } finally {
      await externalDirectory.delete(recursive: true);
    }
  });

  test('creates folders and UTF-8 documents without overwriting', () async {
    final directory = await repository.createDirectory(
      access,
      parentPath: '',
      name: '随笔',
    );
    final document = await repository.createDocument(
      access,
      parentPath: directory.relativePath,
      name: '今日',
      format: DocumentFormat.text,
      initialText: '第一句',
    );

    expect(directory.type, LibraryEntryType.directory);
    expect(document.relativePath, p.join('随笔', '今日.txt'));
    expect(
      await File(p.join(root.path, document.relativePath)).readAsString(),
      '第一句',
    );
    await expectLater(
      repository.createDocument(
        access,
        parentPath: directory.relativePath,
        name: '今日',
        format: DocumentFormat.text,
      ),
      throwsA(
        isA<LibraryOperationException>().having(
          (error) => error.failure.code,
          'code',
          LibraryFailureCode.alreadyExists,
        ),
      ),
    );
  });

  test('reads and preserves UTF-8 BOM and CRLF', () async {
    final file = File(p.join(root.path, '章节.txt'));
    await file.writeAsBytes([
      0xef,
      0xbb,
      0xbf,
      ...utf8.encode('第一行\r\n第二行\r\n'),
    ]);
    const ref = DocumentRef(
      relativePath: '章节.txt',
      format: DocumentFormat.text,
    );

    final loaded = await repository.readDocument(access, ref);
    final saved = await repository.saveDocument(
      access,
      original: loaded,
      text: '${loaded.text}第三行\n',
    );

    expect(loaded.encoding, TextEncoding.utf8Bom);
    expect(loaded.lineEnding, LineEnding.crlf);
    expect(loaded.text, '第一行\n第二行\n');
    expect(saved, isA<DocumentSaveSuccess>());
    final bytes = await file.readAsBytes();
    expect(bytes.take(3), [0xef, 0xbb, 0xbf]);
    expect(utf8.decode(bytes.skip(3).toList()), '第一行\r\n第二行\r\n第三行\r\n');
  });

  test('detects an external modification before saving', () async {
    final file = File(p.join(root.path, '章节.md'));
    await file.writeAsString('原文');
    const ref = DocumentRef(
      relativePath: '章节.md',
      format: DocumentFormat.markdown,
    );
    final loaded = await repository.readDocument(access, ref);
    await file.writeAsString('外部修改');

    final result = await repository.saveDocument(
      access,
      original: loaded,
      text: '本地修改',
    );

    expect(result, isA<DocumentSaveConflict>());
    expect((result as DocumentSaveConflict).diskSnapshot.text, '外部修改');
    expect(await file.readAsString(), '外部修改');
  });

  test('renames documents without changing their extension', () async {
    await File(p.join(root.path, '旧名.md')).writeAsString('');

    final renamed = await repository.renameEntry(
      access,
      relativePath: '旧名.md',
      newName: '新名',
    );

    expect(renamed.name, '新名.md');
    expect(await File(p.join(root.path, '新名.md')).exists(), isTrue);
    await expectLater(
      repository.renameEntry(access, relativePath: '新名.md', newName: '错误.txt'),
      throwsA(
        isA<LibraryOperationException>().having(
          (error) => error.failure.code,
          'code',
          LibraryFailureCode.invalidName,
        ),
      ),
    );
  });

  test('creates a registered novel with body metadata', () async {
    repository = StorageBackedLibraryRepository(
      storageFactory: LocalDirectoryStorageFactory(),
      idGenerator: _IncrementingIdGenerator(),
      clock: _FixedClock(DateTime.utc(2026, 7, 17, 8, 30)),
    );
    await repository.initialize(access);

    final mutation = await repository.createNovel(access, title: '长夜行');

    expect(mutation.snapshot.metadata.title, '长夜行');
    expect(mutation.snapshot.metadata.chapterFormat, ChapterFormat.markdown);
    expect(await Directory(p.join(root.path, '长夜行', '正文')).exists(), isTrue);
    final manifest =
        jsonDecode(
              await File(
                p.join(root.path, '.lore', 'library.json'),
              ).readAsString(),
            )
            as Map<String, Object?>;
    expect(manifest['novels'], hasLength(1));
    final entries = await repository.listChildren(access);
    expect(entries.single.semanticKind, LibraryEntrySemanticKind.novel);
  });

  test('registers and scans an existing novel directory', () async {
    repository = StorageBackedLibraryRepository(
      storageFactory: LocalDirectoryStorageFactory(),
      idGenerator: _IncrementingIdGenerator(),
      clock: _FixedClock(DateTime.utc(2026, 7, 17, 8, 30)),
    );
    await repository.initialize(access);
    final body = Directory(p.join(root.path, '旧作', '正文'));
    await Directory(p.join(body.path, '第一卷')).create(recursive: true);
    await File(p.join(body.path, '序章.md')).writeAsString('序');
    await File(p.join(body.path, '第一卷', '第1章.txt')).writeAsString('章');

    final mutation = await repository.registerExistingNovel(
      access,
      relativePath: '旧作',
    );

    expect(mutation.snapshot.contentTree.nodes, hasLength(3));
    expect(
      mutation.snapshot.contentTree.nodes.where(
        (node) => node.role == ContentRole.prologue,
      ),
      hasLength(1),
    );
    final bodyEntries = await repository.listChildren(
      access,
      relativePath: p.join('旧作', '正文'),
    );
    expect(
      bodyEntries.map((entry) => entry.semanticKind),
      containsAll([
        LibraryEntrySemanticKind.volume,
        LibraryEntrySemanticKind.chapter,
      ]),
    );
  });

  test('creates, moves and reorders chapters with stable identities', () async {
    repository = StorageBackedLibraryRepository(
      storageFactory: LocalDirectoryStorageFactory(),
      idGenerator: _IncrementingIdGenerator(),
      clock: _FixedClock(DateTime.utc(2026, 7, 17, 8, 30)),
    );
    await repository.initialize(access);
    final novel = await repository.createNovel(access, title: '新书');
    final volume = await repository.createVolume(
      access,
      novelId: novel.snapshot.metadata.id,
    );
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
      nodeId: ContentId(second.entry.semanticId!),
      newIndex: 0,
    );
    final moved = await repository.moveChapter(
      access,
      novelId: novel.snapshot.metadata.id,
      chapterId: ContentId(first.entry.semanticId!),
      volumeId: ContentId(volume.entry.semanticId!),
    );

    expect(
      reordered.snapshot.contentTree
          .childrenOf(novel.snapshot.metadata.body.id)
          .first
          .id
          .value,
      second.entry.semanticId,
    );
    expect(moved.entry.semanticId, first.entry.semanticId);
    expect(
      await File(p.join(root.path, moved.entry.relativePath)).exists(),
      isTrue,
    );
  });

  test('renames novel and body while preserving chapter identity', () async {
    repository = StorageBackedLibraryRepository(
      storageFactory: LocalDirectoryStorageFactory(),
      idGenerator: _IncrementingIdGenerator(),
      clock: _FixedClock(DateTime.utc(2026, 7, 17, 8, 30)),
    );
    await repository.initialize(access);
    final novel = await repository.createNovel(access, title: '旧书名');
    final chapter = await repository.createChapter(
      access,
      novelId: novel.snapshot.metadata.id,
    );

    final renamedNovel = await repository.renameNovel(
      access,
      novelId: novel.snapshot.metadata.id,
      newName: '新书名',
    );
    final renamedBody = await repository.renameBody(
      access,
      novelId: novel.snapshot.metadata.id,
      newName: '故事正文',
    );

    expect(renamedNovel.snapshot.metadata.title, '新书名');
    expect(renamedBody.snapshot.metadata.body.relativePath, '故事正文');
    expect(
      renamedBody.snapshot.contentTree.nodes.single.id.value,
      chapter.entry.semanticId,
    );
    expect(
      await File(
        p.join(
          root.path,
          '新书名',
          renamedBody.snapshot.contentTree.nodes.single.relativePath,
        ),
      ).exists(),
      isTrue,
    );
  });

  test(
    'recovers an interrupted body rename without changing chapter ids',
    () async {
      repository = StorageBackedLibraryRepository(
        storageFactory: LocalDirectoryStorageFactory(),
        idGenerator: _IncrementingIdGenerator(),
        clock: _FixedClock(DateTime.utc(2026, 7, 17, 8, 30)),
      );
      await repository.initialize(access);
      final novel = await repository.createNovel(access, title: '恢复测试');
      final chapter = await repository.createChapter(
        access,
        novelId: novel.snapshot.metadata.id,
      );
      await Directory(
        p.join(root.path, '恢复测试', '正文'),
      ).rename(p.join(root.path, '恢复测试', '故事正文'));
      final pending = File(
        p.join(root.path, '.lore', 'recovery', 'pending-operation.json'),
      );
      await pending.parent.create(recursive: true);
      await pending.writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'novelId': novel.snapshot.metadata.id.value,
          'novelPath': '恢复测试',
          'operation': 'renameBody',
          'sourcePath': p.join('恢复测试', '正文'),
          'targetPath': p.join('恢复测试', '故事正文'),
          'startedAt': '2026-07-17T08:30:00.000Z',
        }),
      );

      expect(await repository.inspect(access), isA<LibraryInspectionReady>());
      final recovered = await repository.loadNovel(
        access,
        novelId: novel.snapshot.metadata.id,
      );

      expect(recovered.metadata.body.relativePath, '故事正文');
      expect(
        recovered.contentTree.nodes.single.id.value,
        chapter.entry.semanticId,
      );
      expect(await pending.exists(), isFalse);
    },
  );

  test('rejects novel metadata paths outside the novel directory', () async {
    repository = StorageBackedLibraryRepository(
      storageFactory: LocalDirectoryStorageFactory(),
      idGenerator: _IncrementingIdGenerator(),
      clock: _FixedClock(DateTime.utc(2026, 7, 17, 8, 30)),
    );
    await repository.initialize(access);
    final novel = await repository.createNovel(access, title: '路径测试');
    final novelFile = File(p.join(root.path, '路径测试', '.lore', 'novel.json'));
    final metadata =
        jsonDecode(await novelFile.readAsString()) as Map<String, Object?>;
    final body = metadata['body']! as Map<String, Object?>;
    body['path'] = p.join('..', '..', '书库外');
    await novelFile.writeAsString(jsonEncode(metadata));

    await expectLater(
      repository.loadNovel(access, novelId: novel.snapshot.metadata.id),
      throwsA(
        isA<LibraryOperationException>().having(
          (error) => error.failure.code,
          'code',
          LibraryFailureCode.metadataCorrupt,
        ),
      ),
    );
    expect(await Directory(p.join(root.parent.path, '书库外')).exists(), isFalse);
  });

  test(
    'listNovels reports corrupt novel metadata instead of hiding it',
    () async {
      repository = StorageBackedLibraryRepository(
        storageFactory: LocalDirectoryStorageFactory(),
        idGenerator: _IncrementingIdGenerator(),
        clock: _FixedClock(DateTime.utc(2026, 7, 17, 8, 30)),
      );
      await repository.initialize(access);
      await repository.createNovel(access, title: '损坏测试');
      final novelFile = File(p.join(root.path, '损坏测试', '.lore', 'novel.json'));
      final metadata =
          jsonDecode(await novelFile.readAsString()) as Map<String, Object?>;
      metadata['chapterFormat'] = 'unknown';
      await novelFile.writeAsString(jsonEncode(metadata));

      await expectLater(
        repository.listNovels(access),
        throwsA(
          isA<LibraryOperationException>().having(
            (error) => error.failure.code,
            'code',
            LibraryFailureCode.metadataCorrupt,
          ),
        ),
      );
    },
  );

  test('rejects unknown content node roles as corrupt metadata', () async {
    repository = StorageBackedLibraryRepository(
      storageFactory: LocalDirectoryStorageFactory(),
      idGenerator: _IncrementingIdGenerator(),
      clock: _FixedClock(DateTime.utc(2026, 7, 17, 8, 30)),
    );
    await repository.initialize(access);
    final novel = await repository.createNovel(access, title: '角色测试');
    await repository.createChapter(access, novelId: novel.snapshot.metadata.id);
    final contentFile = File(
      p.join(root.path, '角色测试', '.lore', 'content.json'),
    );
    final content =
        jsonDecode(await contentFile.readAsString()) as Map<String, Object?>;
    final node =
        (content['nodes']! as List<Object?>).single as Map<String, Object?>;
    node['role'] = 'unknown';
    await contentFile.writeAsString(jsonEncode(content));

    await expectLater(
      repository.loadNovel(access, novelId: novel.snapshot.metadata.id),
      throwsA(
        isA<LibraryOperationException>().having(
          (error) => error.failure.code,
          'code',
          LibraryFailureCode.metadataCorrupt,
        ),
      ),
    );
  });

  test('does not commit a pending rename before the file moved', () async {
    repository = StorageBackedLibraryRepository(
      storageFactory: LocalDirectoryStorageFactory(),
      idGenerator: _IncrementingIdGenerator(),
      clock: _FixedClock(DateTime.utc(2026, 7, 17, 8, 30)),
    );
    await repository.initialize(access);
    final novel = await repository.createNovel(access, title: '恢复测试');
    final chapter = await repository.createChapter(
      access,
      novelId: novel.snapshot.metadata.id,
    );
    final sourcePath = chapter.entry.relativePath;
    final targetPath = p.join(p.dirname(sourcePath), '改名后.md');
    final pending = File(
      p.join(root.path, '.lore', 'recovery', 'pending-operation.json'),
    );
    await pending.writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'novelId': novel.snapshot.metadata.id.value,
        'novelPath': '恢复测试',
        'operation': 'renameNode',
        'sourcePath': sourcePath,
        'targetPath': targetPath,
        'startedAt': '2026-07-17T08:30:00.000Z',
      }),
    );

    expect(await repository.inspect(access), isA<LibraryInspectionReady>());
    final recovered = await repository.loadNovel(
      access,
      novelId: novel.snapshot.metadata.id,
    );

    expect(recovered.contentTree.nodes, hasLength(1));
    expect(
      recovered.contentTree.nodes.single.id.value,
      chapter.entry.semanticId,
    );
    expect(
      recovered.contentTree.nodes.single.relativePath,
      p.relative(sourcePath, from: '恢复测试'),
    );
    expect(await File(p.join(root.path, sourcePath)).exists(), isTrue);
    expect(await File(p.join(root.path, targetPath)).exists(), isFalse);
  });

  test('preserves volume and chapter ids after an external rename', () async {
    repository = StorageBackedLibraryRepository(
      storageFactory: LocalDirectoryStorageFactory(),
      idGenerator: _IncrementingIdGenerator(),
      clock: _FixedClock(DateTime.utc(2026, 7, 17, 8, 30)),
    );
    await repository.initialize(access);
    final novel = await repository.createNovel(access, title: '外部改名');
    final volume = await repository.createVolume(
      access,
      novelId: novel.snapshot.metadata.id,
    );
    final chapter = await repository.createChapter(
      access,
      novelId: novel.snapshot.metadata.id,
      volumeId: ContentId(volume.entry.semanticId!),
    );
    final renamedVolumePath = p.join('外部改名', '正文', '新卷名');
    await Directory(
      p.join(root.path, volume.entry.relativePath),
    ).rename(p.join(root.path, renamedVolumePath));

    final result = await repository.reconcile(
      access,
      novelId: novel.snapshot.metadata.id,
    );

    expect(result.issues, isEmpty);
    expect(result.snapshot.contentTree.nodes, hasLength(2));
    final recoveredVolume = result.snapshot.contentTree.nodeById(
      ContentId(volume.entry.semanticId!),
    );
    final recoveredChapter = result.snapshot.contentTree.nodeById(
      ContentId(chapter.entry.semanticId!),
    );
    expect(recoveredVolume?.relativePath, p.join('正文', '新卷名'));
    expect(
      recoveredChapter?.relativePath,
      p.join('正文', '新卷名', p.basename(chapter.entry.relativePath)),
    );
  });

  test('rejects direct access to internal metadata', () async {
    await repository.initialize(access);

    await expectLater(
      repository.listChildren(access, relativePath: '.lore'),
      throwsA(
        isA<LibraryOperationException>().having(
          (error) => error.failure.code,
          'code',
          LibraryFailureCode.invalidLocation,
        ),
      ),
    );
  });
}

final class _SequenceIdGenerator implements IdGenerator {
  var _index = 0;

  @override
  String generate() {
    _index += 1;
    return switch (_index) {
      1 => '11111111-1111-4111-8111-111111111111',
      _ => '22222222-2222-4222-8222-222222222222',
    };
  }
}

final class _FixedClock implements Clock {
  const _FixedClock(this.value);

  final DateTime value;

  @override
  DateTime nowUtc() => value;
}

final class _CreatingIdGenerator implements IdGenerator {
  const _CreatingIdGenerator(this.manifest, this.content);

  final File manifest;
  final String content;

  @override
  String generate() {
    manifest.writeAsStringSync(content);
    return '11111111-1111-4111-8111-111111111111';
  }
}

final class _IncrementingIdGenerator implements IdGenerator {
  var _value = 0;

  @override
  String generate() {
    _value += 1;
    return '00000000-0000-4000-8000-${_value.toString().padLeft(12, '0')}';
  }
}
