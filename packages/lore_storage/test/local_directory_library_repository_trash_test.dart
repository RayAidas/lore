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
    root = await Directory.systemTemp.createTemp('lore-trash-test-');
    access = LibraryAccess(
      token: root.path,
      displayPath: root.path,
      isPending: false,
    );
    repository = StorageBackedLibraryRepository(
      storageFactory: LocalDirectoryStorageFactory(),
      idGenerator: _IncrementingIdGenerator(),
      clock: _FixedClock(DateTime.utc(2026, 7, 17, 8, 30)),
    );
    await repository.initialize(access);
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('deleteNode moves chapter into trash and records manifest', () async {
    final novel = await repository.createNovel(access, title: 'TestNovel');
    final novelId = novel.snapshot.metadata.id;
    final chapter = await repository.createChapter(access, novelId: novelId);
    final chapterNodeId = ContentId(chapter.entry.semanticId!);
    final chapterPath = p.join(root.path, 'TestNovel', '正文', '第1章.md');
    expect(await File(chapterPath).exists(), isTrue);

    final result = await repository.deleteNode(
      access,
      novelId: novelId,
      nodeId: chapterNodeId,
    );

    expect(await File(chapterPath).exists(), isFalse);
    expect(result.removedNodeIds, contains(chapterNodeId));
    final items = await repository.listItems(access);
    expect(items, hasLength(1));
    expect(items.single.token, result.trashToken);
    expect(items.single.type, TrashItemType.chapter);
    final reloaded = await repository.loadNovel(access, novelId: novelId);
    expect(
      reloaded.contentTree.nodes.any((node) => node.id == chapterNodeId),
      isFalse,
    );
  });

  test('deleteNode on volume recursively removes child chapters', () async {
    final novel = await repository.createNovel(access, title: 'TestNovel');
    final novelId = novel.snapshot.metadata.id;
    final volume = await repository.createVolume(access, novelId: novelId);
    final volumeNodeId = ContentId(volume.entry.semanticId!);
    await repository.createChapter(
      access,
      novelId: novelId,
      volumeId: volumeNodeId,
    );

    final result = await repository.deleteNode(
      access,
      novelId: novelId,
      nodeId: volumeNodeId,
    );

    expect(result.removedNodeIds.length, 2); // 卷 + 1 章
    final reloaded = await repository.loadNovel(access, novelId: novelId);
    expect(reloaded.contentTree.nodes, isEmpty);
  });

  test('restore moves chapter back and clears manifest', () async {
    final novel = await repository.createNovel(access, title: 'TestNovel');
    final novelId = novel.snapshot.metadata.id;
    final chapter = await repository.createChapter(access, novelId: novelId);
    final chapterNodeId = ContentId(chapter.entry.semanticId!);
    final chapterPath = p.join(root.path, 'TestNovel', '正文', '第1章.md');
    final result = await repository.deleteNode(
      access,
      novelId: novelId,
      nodeId: chapterNodeId,
    );

    await repository.restore(access, trashToken: result.trashToken);

    expect(await File(chapterPath).exists(), isTrue);
    expect(await repository.listItems(access), isEmpty);
    final reloaded = await repository.loadNovel(access, novelId: novelId);
    // 章节文件已回到正文目录，scan 重建出 1 个章节节点。
    expect(
      reloaded.contentTree.nodes
          .where((node) => node.type == ContentNodeType.chapter)
          .length,
      1,
    );
  });

  test('restores legacy chapter trash records into the content tree', () async {
    final novel = await repository.createNovel(access, title: 'TestNovel');
    final novelId = novel.snapshot.metadata.id;
    final chapter = await repository.createChapter(access, novelId: novelId);
    final chapterNodeId = ContentId(chapter.entry.semanticId!);
    final deletion = await repository.deleteNode(
      access,
      novelId: novelId,
      nodeId: chapterNodeId,
    );
    final manifestFile = File(
      p.join(root.path, '.lore', 'trash', 'index.json'),
    );
    final manifest =
        jsonDecode(await manifestFile.readAsString()) as Map<String, Object?>;
    final item =
        (manifest['items']! as List<Object?>).single as Map<String, Object?>;
    item['originalRelativePath'] = item.remove('originalPath');
    item['trashRelativePath'] = item.remove('trashPath');
    item['children'] = <Object?>[];
    item.remove('nodes');
    item.remove('pending');
    await manifestFile.writeAsString(jsonEncode(manifest));

    await repository.restore(access, trashToken: deletion.trashToken);

    final restored = await repository.loadNovel(access, novelId: novelId);
    expect(restored.contentTree.nodes, hasLength(1));
    expect(restored.contentTree.nodes.single.id, chapterNodeId);
  });

  test('restores legacy volume children with stable identities', () async {
    final novel = await repository.createNovel(access, title: 'TestNovel');
    final novelId = novel.snapshot.metadata.id;
    final volume = await repository.createVolume(access, novelId: novelId);
    final volumeNodeId = ContentId(volume.entry.semanticId!);
    final chapter = await repository.createChapter(
      access,
      novelId: novelId,
      volumeId: volumeNodeId,
    );
    final chapterNodeId = ContentId(chapter.entry.semanticId!);
    final deletion = await repository.deleteNode(
      access,
      novelId: novelId,
      nodeId: volumeNodeId,
    );
    final manifestFile = File(
      p.join(root.path, '.lore', 'trash', 'index.json'),
    );
    final manifest =
        jsonDecode(await manifestFile.readAsString()) as Map<String, Object?>;
    final item =
        (manifest['items']! as List<Object?>).single as Map<String, Object?>;
    final originalPath = item.remove('originalPath')! as String;
    final trashPath = item.remove('trashPath')! as String;
    final nodes = item.remove('nodes')! as List<Object?>;
    item['originalRelativePath'] = originalPath;
    item['trashRelativePath'] = trashPath;
    item['children'] = nodes
        .cast<Map<String, Object?>>()
        .where((node) => node['id'] != volumeNodeId.value)
        .map((node) {
          final relativePath = node['path']! as String;
          return {
            'nodeId': node['id'],
            'originalRelativePath': p.join('TestNovel', relativePath),
            'trashRelativePath': p.join(
              '.lore',
              'trash',
              deletion.trashToken,
              'TestNovel',
              relativePath,
            ),
          };
        })
        .toList();
    item.remove('pending');
    await manifestFile.writeAsString(jsonEncode(manifest));

    await repository.restore(access, trashToken: deletion.trashToken);

    final restored = await repository.loadNovel(access, novelId: novelId);
    expect(restored.contentTree.nodeById(volumeNodeId), isNotNull);
    expect(restored.contentTree.nodeById(chapterNodeId), isNotNull);
  });

  test(
    'restore with rename strategy avoids overwriting existing file',
    () async {
      final novel = await repository.createNovel(access, title: 'TestNovel');
      final novelId = novel.snapshot.metadata.id;
      final chapter = await repository.createChapter(access, novelId: novelId);
      final chapterNodeId = ContentId(chapter.entry.semanticId!);
      final originalPath = p.join(root.path, 'TestNovel', '正文', '第1章.md');
      final result = await repository.deleteNode(
        access,
        novelId: novelId,
        nodeId: chapterNodeId,
      );

      // 原位置重新出现同名文件（模拟用户在删除后新建了同名章节）。
      await File(originalPath).writeAsString('新建内容');

      await repository.restore(
        access,
        trashToken: result.trashToken,
        strategy: RestoreConflictStrategy.rename,
      );

      expect(await File(originalPath).exists(), isTrue);
      final bodyDir = Directory(p.join(root.path, 'TestNovel', '正文'));
      final mdFiles = await bodyDir
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.md'))
          .toList();
      expect(mdFiles.length, 2); // 原文件 + 恢复副本
    },
  );

  test('purge permanently removes trash item', () async {
    final novel = await repository.createNovel(access, title: 'TestNovel');
    final novelId = novel.snapshot.metadata.id;
    final chapter = await repository.createChapter(access, novelId: novelId);
    final chapterNodeId = ContentId(chapter.entry.semanticId!);
    final result = await repository.deleteNode(
      access,
      novelId: novelId,
      nodeId: chapterNodeId,
    );

    await repository.purge(access, trashToken: result.trashToken);

    expect(await repository.listItems(access), isEmpty);
    expect(
      await Directory(
        p.join(root.path, '.lore', 'trash', result.trashToken),
      ).exists(),
      isFalse,
    );
  });

  test('deleteNovel moves novel into trash and removes registration', () async {
    final novel = await repository.createNovel(access, title: 'TestNovel');
    final novelId = novel.snapshot.metadata.id;

    await repository.deleteNovel(access, novelId: novelId);

    expect(await Directory(p.join(root.path, 'TestNovel')).exists(), isFalse);
    expect(await repository.listNovels(access), isEmpty);
    final items = await repository.listItems(access);
    expect(items, hasLength(1));
    expect(items.single.type, TrashItemType.novel);
  });

  test('deleteEntry moves generic file into trash', () async {
    await repository.createDocument(
      access,
      parentPath: '',
      name: 'note',
      format: DocumentFormat.text,
    );
    final filePath = p.join(root.path, 'note.txt');
    expect(await File(filePath).exists(), isTrue);

    await repository.deleteEntry(access, relativePath: 'note.txt');

    expect(await File(filePath).exists(), isFalse);
    final items = await repository.listItems(access);
    expect(items, hasLength(1));
    expect(items.single.type, TrashItemType.entry);
  });

  test(
    'recoverPending tolerates trashEntry pending with empty novelPath',
    () async {
      // 模拟 trashEntry 崩溃：残留 pending-operation.json，novelPath 为空。
      final pendingFile = File(
        p.join(root.path, '.lore', 'recovery', 'pending-operation.json'),
      );
      await pendingFile.parent.create(recursive: true);
      await pendingFile.writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'novelId': '00000000-0000-4000-8000-000000000000',
          'novelPath': '',
          'operation': 'trashEntry',
          'sourcePath': null,
          'targetPath': null,
          'startedAt': '2026-07-17T08:30:00Z',
        }),
      );

      // inspect 触发 _recoverPending，不应抛 metadataCorrupt。
      final inspection = await repository.inspect(access);
      expect(inspection, isA<LibraryInspectionReady>());
      expect(await pendingFile.exists(), isFalse);
    },
  );

  test('restore re-registers deleted novel in library manifest', () async {
    final novel = await repository.createNovel(access, title: 'TestNovel');
    final novelId = novel.snapshot.metadata.id;
    await repository.deleteNovel(access, novelId: novelId);
    expect(await repository.listNovels(access), isEmpty);

    final items = await repository.listItems(access);
    await repository.restore(access, trashToken: items.single.token);

    final novels = await repository.listNovels(access);
    expect(novels, hasLength(1));
    expect(novels.single.metadata.id, novelId);
  });

  test('listItems reconciles orphan trash directories', () async {
    // 模拟崩溃：手动把文件放进 .lore/trash/<token>/，但 manifest 无记录。
    final orphanDir = Directory(
      p.join(root.path, '.lore', 'trash', 'orphan-token'),
    );
    await orphanDir.create(recursive: true);
    await File(p.join(orphanDir.path, 'note.txt')).writeAsString('x');

    final items = await repository.listItems(access);

    expect(items, hasLength(1));
    expect(items.single.token, 'orphan-token');
    expect(items.single.originalRelativePath, 'note.txt');
    expect(items.single.type, TrashItemType.entry);
    // 对账后写盘，再次读取仍可见。
    expect((await repository.listItems(access)).single.token, 'orphan-token');
  });
}

final class _IncrementingIdGenerator implements IdGenerator {
  var _value = 0;

  @override
  String generate() {
    _value += 1;
    return '00000000-0000-4000-8000-${_value.toString().padLeft(12, '0')}';
  }
}

final class _FixedClock implements Clock {
  const _FixedClock(this.value);

  final DateTime value;

  @override
  DateTime nowUtc() => value;
}
