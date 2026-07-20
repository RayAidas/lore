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
    'importNovel writes chapter files, content.json and registration',
    () async {
      final mutation = await repository.importNovel(
        access,
        title: '导入小说',
        chapters: const [
          NovelChapterImport(subtitle: '起点', body: '起点正文。'),
          NovelChapterImport(subtitle: '远行', body: '远行正文。\n第二段。'),
        ],
      );

      // 目录结构：正文/第1章 起点.txt 与 第2章 远行.txt。
      expect(
        await File('${root.path}/导入小说/正文/第1章 起点.txt').readAsString(),
        '第1章 起点\n起点正文。',
      );
      expect(
        await File('${root.path}/导入小说/正文/第2章 远行.txt').readAsString(),
        '第2章 远行\n远行正文。\n第二段。',
      );

      // 元数据落盘 + 注册到 library.json。
      expect(await File('${root.path}/导入小说/.lore/novel.json').exists(), isTrue);
      expect(
        await File('${root.path}/导入小说/.lore/content.json').exists(),
        isTrue,
      );
      final novels = await repository.listNovels(access);
      expect(novels.single.metadata.title, '导入小说');

      // 扁平结构：两章都挂在正文下，顺序编号、role=normal、字数回填。
      final snapshot = mutation.snapshot;
      final chapters = snapshot.contentTree.nodes;
      expect(chapters, hasLength(2));
      expect(chapters[0].number, 1);
      expect(chapters[0].role, ContentRole.normal);
      expect(chapters[0].parentId, snapshot.metadata.body.id);
      expect(chapters[0].characterCount, 5); // 「起点正文。」去标点空白后 5 runes
      expect(chapters[1].number, 2);
      expect(chapters[1].characterCount, 9); // 「远行正文。第二段。」= 9 runes
    },
  );

  test(
    'importNovel falls back to 第N章 filename when subtitle is empty',
    () async {
      final mutation = await repository.importNovel(
        access,
        title: '无副标题',
        chapters: const [NovelChapterImport(subtitle: '', body: '只有正文。')],
      );
      expect(mutation.snapshot.contentTree.nodes.single.number, 1);
      expect(
        await File('${root.path}/无副标题/正文/第1章.txt').readAsString(),
        '第1章\n只有正文。',
      );
    },
  );

  test(
    'importNovel keeps distinct filenames via seq even with equal subtitles',
    () async {
      await repository.importNovel(
        access,
        title: '撞副标题',
        chapters: const [
          NovelChapterImport(subtitle: '同名', body: 'A'),
          NovelChapterImport(subtitle: '同名', body: 'B'),
        ],
      );
      // seq 不同（第1章 / 第2章）即天然区分，无需后缀。
      expect(await File('${root.path}/撞副标题/正文/第1章 同名.txt').exists(), isTrue);
      expect(await File('${root.path}/撞副标题/正文/第2章 同名.txt').exists(), isTrue);
    },
  );

  test(
    'importNovel rejects a duplicate novel title with alreadyExists',
    () async {
      await repository.importNovel(
        access,
        title: '重名',
        chapters: const [NovelChapterImport(subtitle: '', body: 'x')],
      );
      await expectLater(
        repository.importNovel(
          access,
          title: '重名',
          chapters: const [NovelChapterImport(subtitle: '', body: 'y')],
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
      chapters: const [NovelChapterImport(subtitle: '首章', body: '正文。')],
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
