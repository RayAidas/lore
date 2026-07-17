import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_storage/lore_storage.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late LocalDirectoryLibraryRepository repository;
  late LibraryAccess access;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lore-library-test-');
    access = LibraryAccess(
      token: root.path,
      displayPath: root.path,
      isPending: false,
    );
    repository = LocalDirectoryLibraryRepository(
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

    expect(metadata.schemaVersion, 1);
    expect(metadata.id.value, '11111111-1111-4111-8111-111111111111');
    expect(await existing.readAsString(), '保留内容');
    final manifest = File(p.join(root.path, '.lore', 'library.json'));
    expect(await manifest.exists(), isTrue);
    final json =
        jsonDecode(await manifest.readAsString()) as Map<String, Object?>;
    expect(json['schemaVersion'], 1);
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
    repository = LocalDirectoryLibraryRepository(
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
