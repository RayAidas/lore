import 'dart:io';

import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_storage/lore_storage.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late StorageBackedLibraryRepository repository;
  late LibraryAccess access;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lore-import-repository-');
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
    await repository.initialize(access);
  });

  tearDown(() => root.delete(recursive: true));

  test(
    'importNovel writes flat root chapters, content.json and registration',
    () async {
      final mutation = await repository.importNovel(
        access,
        title: '导入小说',
        sections: [
          ParsedRootChapters([
            NovelChapterImport(subtitle: '起点', body: '起点正文。'),
            NovelChapterImport(subtitle: '远行', body: '远行正文。\n第二段。'),
          ]),
        ],
      );

      expect(
        await File('${root.path}/导入小说/正文/第1章 起点.txt').readAsString(),
        '第1章 起点\n起点正文。',
      );
      expect(
        await File('${root.path}/导入小说/正文/第2章 远行.txt').readAsString(),
        '第2章 远行\n远行正文。\n第二段。',
      );
      expect(await File('${root.path}/导入小说/.lore/novel.json').exists(), isTrue);
      expect(
        await File('${root.path}/导入小说/.lore/content.json').exists(),
        isTrue,
      );
      final novels = await repository.listNovels(access);
      expect(novels.single.metadata.title, '导入小说');

      final chapters = mutation.snapshot.contentTree.nodes;
      expect(chapters, hasLength(2));
      expect(chapters[0].number, 1);
      expect(chapters[0].parentId, mutation.snapshot.metadata.body.id);
      expect(chapters[0].characterCount, 5);
      expect(chapters[1].number, 2);
      expect(chapters[1].characterCount, 9);
    },
  );

  test('importNovel creates volume folders with nested chapters', () async {
    final mutation = await repository.importNovel(
      access,
      title: '卷小说',
      sections: [
        ParsedRootChapters([NovelChapterImport(subtitle: '地府', body: '地府正文。')]),
        ParsedVolume(
          name: '破茧成蝶',
          chapters: [
            NovelChapterImport(subtitle: '水府四殿', body: '水府正文。'),
            NovelChapterImport(subtitle: '珍宝', body: '珍宝正文。'),
          ],
        ),
      ],
    );

    // 根章节直接在正文下；卷章节在卷目录下。
    expect(await File('${root.path}/卷小说/正文/第1章 地府.txt').exists(), isTrue);
    expect(
      await File('${root.path}/卷小说/正文/第1卷 破茧成蝶/第2章 水府四殿.txt').exists(),
      isTrue,
    );
    expect(
      await File('${root.path}/卷小说/正文/第1卷 破茧成蝶/第3章 珍宝.txt').exists(),
      isTrue,
    );
    expect(await Directory('${root.path}/卷小说/正文/第1卷 破茧成蝶').exists(), isTrue);

    final nodes = mutation.snapshot.contentTree.nodes;
    final volumes = nodes
        .where((n) => n.type == ContentNodeType.volume)
        .toList();
    final chapters = nodes
        .where((n) => n.type == ContentNodeType.chapter)
        .toList();
    expect(volumes, hasLength(1));
    expect(volumes.single.number, 1);
    expect(chapters, hasLength(3));
    // 章节编号全局连续 1..3。
    expect(chapters.map((c) => c.number), [1, 2, 3]);
    // 卷内章节挂在卷 id 下。
    final volId = volumes.single.id;
    expect(chapters[1].parentId, volId);
    expect(chapters[2].parentId, volId);
    // 根章节挂在正文 id 下。
    expect(chapters[0].parentId, mutation.snapshot.metadata.body.id);
  });

  test(
    'importNovel rejects a duplicate novel title with alreadyExists',
    () async {
      await repository.importNovel(
        access,
        title: '重名',
        sections: [
          ParsedRootChapters([NovelChapterImport(subtitle: '', body: 'x')]),
        ],
      );
      await expectLater(
        repository.importNovel(
          access,
          title: '重名',
          sections: [
            ParsedRootChapters([NovelChapterImport(subtitle: '', body: 'y')]),
          ],
        ),
        throwsA(
          isA<LibraryOperationException>().having(
            (error) => error.failure.code,
            'code',
            LibraryFailureCode.alreadyExists,
          ),
        ),
      );
    },
  );

  test('importNovel honors markdown chapter format', () async {
    final mutation = await repository.importNovel(
      access,
      title: 'MD 导入',
      chapterFormat: ChapterFormat.markdown,
      sections: [
        ParsedRootChapters([NovelChapterImport(subtitle: '首章', body: '正文。')]),
      ],
    );
    expect(mutation.snapshot.metadata.chapterFormat, ChapterFormat.markdown);
    expect(
      await File('${root.path}/MD 导入/正文/第1章 首章.md').readAsString(),
      '# 第1章 首章\n正文。',
    );
  });
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
