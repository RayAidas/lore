import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:test/test.dart';

void main() {
  const novelId = NovelId('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
  const bodyId = ContentId('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
  const volumeId = ContentId('cccccccc-cccc-4ccc-8ccc-cccccccccccc');
  const rootChapterId = ContentId('dddddddd-dddd-4ddd-8ddd-dddddddddddd');
  const volChapter1Id = ContentId('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
  const volChapter2Id = ContentId('ffffffff-ffff-4fff-8fff-ffffffffffff');

  final session = LibrarySession(
    access: const LibraryAccess(
      token: '/tmp/lib',
      displayPath: '/tmp/lib',
      isPending: false,
    ),
    metadata: LibraryMetadata(
      schemaVersion: 1,
      id: const LibraryId('lib'),
      createdAt: DateTime.utc(2026, 7, 17),
      updatedAt: DateTime.utc(2026, 7, 17),
    ),
  );

  NovelSnapshot snapshot() => NovelSnapshot(
    rootPath: 'novel',
    metadata: NovelMetadata(
      schemaVersion: 1,
      id: novelId,
      title: 'novel',
      description: '',
      coverPath: null,
      body: const NovelBody(id: bodyId, relativePath: '正文'),
      chapterFormat: ChapterFormat.markdown,
      numberingMode: NumberingMode.continuous,
      createdAt: DateTime.utc(2026, 7, 17),
      updatedAt: DateTime.utc(2026, 7, 17),
    ),
    contentTree: const ContentTree(
      schemaVersion: 1,
      novelId: novelId,
      revision: 1,
      nodes: [
        ContentNode(
          id: volumeId,
          type: ContentNodeType.volume,
          parentId: bodyId,
          relativePath: '正文/第一卷',
          order: 1000,
          number: 1,
          role: ContentRole.normal,
        ),
        ContentNode(
          id: rootChapterId,
          type: ContentNodeType.chapter,
          parentId: bodyId,
          relativePath: '正文/序章.md',
          order: 2000,
          number: null,
          role: ContentRole.prologue,
        ),
        ContentNode(
          id: volChapter1Id,
          type: ContentNodeType.chapter,
          parentId: volumeId,
          relativePath: '正文/第一卷/第1章.md',
          order: 1000,
          number: 1,
          role: ContentRole.normal,
        ),
        ContentNode(
          id: volChapter2Id,
          type: ContentNodeType.chapter,
          parentId: volumeId,
          relativePath: '正文/第一卷/第2章.md',
          order: 2000,
          number: 2,
          role: ContentRole.normal,
        ),
      ],
    ),
  );

  test('counts characters across chapters and aggregates per volume', () async {
    final now = DateTime.utc(2026, 7, 17);
    final progress = _FakeWritingProgressRepository();
    await progress.addDelta(novelId, now, 250);

    final service = NovelOverviewService(
      novelRepository: _FakeNovelRepository(snapshot()),
      documentRepository: _FakeDocumentRepository({
        'novel/正文/序章.md': 'hello', // 5
        'novel/正文/第一卷/第1章.md': 'hello world', // 10 (space stripped)
        'novel/正文/第一卷/第2章.md': 'foo', // 3
      }),
      clock: _FixedClock(now),
      writingProgressRepository: progress,
    );

    final overview = await service.computeOverview(
      session,
      novelId: novelId,
      dailyWordGoal: 1000,
    );

    expect(overview.chapterCount, 3);
    expect(overview.volumeCount, 1);
    expect(overview.totalCharacterCount, 18); // 5 + 10 + 3
    expect(overview.todayCharacterCount, 250);
    expect(overview.dailyWordGoal, 1000);
    expect(overview.volumeSummaries.single.chapterCount, 2);
    expect(overview.volumeSummaries.single.characterCount, 13); // 10 + 3
  });

  test('reports zero today when progress repository absent', () async {
    final service = NovelOverviewService(
      novelRepository: _FakeNovelRepository(snapshot()),
      documentRepository: _FakeDocumentRepository(const {}),
      clock: _FixedClock(DateTime.utc(2026, 7, 17)),
    );
    final overview = await service.computeOverview(session, novelId: novelId);
    expect(overview.todayCharacterCount, 0);
    expect(overview.totalCharacterCount, 0);
  });
}

final class _FakeNovelRepository implements NovelRepository {
  _FakeNovelRepository(this._snapshot);
  final NovelSnapshot _snapshot;

  @override
  Future<NovelSnapshot> loadNovel(
    LibraryAccess access, {
    required NovelId novelId,
  }) async => _snapshot;

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _FakeDocumentRepository implements DocumentRepository {
  _FakeDocumentRepository(this._texts);
  final Map<String, String> _texts;

  @override
  Future<DocumentSnapshot> readDocument(
    LibraryAccess access,
    DocumentRef ref,
  ) async {
    final text = _texts[ref.relativePath];
    if (text == null) {
      throw const LibraryOperationException(
        LibraryFailure(code: LibraryFailureCode.notFound, message: 'missing'),
      );
    }
    return DocumentSnapshot(
      ref: ref,
      text: text,
      encoding: TextEncoding.utf8,
      lineEnding: LineEnding.lf,
      revision: const DocumentRevision('rev'),
    );
  }

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _FakeWritingProgressRepository
    implements WritingProgressRepository {
  final Map<String, int> _counts = {};

  String _dayKey(DateTime utc) =>
      '${utc.year.toString().padLeft(4, '0')}-'
      '${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')}';

  @override
  Future<int> loadToday(NovelId novelId, DateTime todayUtc) async =>
      _counts[_dayKey(todayUtc)] ?? 0;

  @override
  Future<void> addDelta(NovelId novelId, DateTime todayUtc, int delta) async {
    final key = _dayKey(todayUtc);
    _counts[key] = (_counts[key] ?? 0) + delta;
  }

  @override
  Future<void> pruneBefore(DateTime cutoffUtc) async {}
}

final class _FixedClock implements Clock {
  _FixedClock(this._now);
  final DateTime _now;
  @override
  DateTime nowUtc() => _now;
}
