import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:test/test.dart';

void main() {
  const libraryId = LibraryId('library');
  const novelId = NovelId('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');

  test(
    'computes week totals, active days, streak, and a complete month',
    () async {
      final repository = _FakeProgressRepository()
        ..put(libraryId, novelId, WritingDay(2026, 7, 20), 200)
        ..put(libraryId, novelId, WritingDay(2026, 7, 21), -10)
        ..put(libraryId, novelId, WritingDay(2026, 7, 22), 300);
      final service = WritingStatisticsService(repository);

      final result = await service.computeNovel(
        libraryId,
        novelId,
        today: WritingDay(2026, 7, 22),
      );

      expect(result.todayNetDelta, 300);
      expect(result.weekNetDelta, 490);
      expect(result.activeDaysThisWeek, 2);
      expect(result.currentStreakDays, 1);
      expect(result.monthDays, hasLength(31));
      expect(result.monthDays[19].netDelta, 200);
    },
  );

  test(
    'aggregates all novels in a library without crossing library boundaries',
    () async {
      final repository = _FakeProgressRepository()
        ..put(libraryId, novelId, WritingDay(2026, 7, 22), 300)
        ..put(
          libraryId,
          const NovelId('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
          WritingDay(2026, 7, 22),
          100,
        )
        ..put(const LibraryId('other'), novelId, WritingDay(2026, 7, 22), 900);
      final service = WritingStatisticsService(repository);

      final result = await service.computeLibrary(
        libraryId,
        today: WritingDay(2026, 7, 22),
      );

      expect(result.todayNetDelta, 400);
      expect(result.weekNetDelta, 400);
    },
  );

  test(
    'keeps current summary metrics when displaying a previous month',
    () async {
      final repository = _FakeProgressRepository()
        ..put(libraryId, novelId, WritingDay(2026, 6, 15), 180)
        ..put(libraryId, novelId, WritingDay(2026, 7, 20), 200)
        ..put(libraryId, novelId, WritingDay(2026, 7, 22), 300);
      final service = WritingStatisticsService(repository);

      final result = await service.computeNovel(
        libraryId,
        novelId,
        today: WritingDay(2026, 7, 22),
        month: WritingDay(2026, 6, 1),
      );

      expect(result.todayNetDelta, 300);
      expect(result.weekNetDelta, 500);
      expect(result.currentStreakDays, 1);
      expect(result.monthDays[14].netDelta, 180);
    },
  );
}

final class _FakeProgressRepository implements WritingProgressRepository {
  final Map<(LibraryId, NovelId, WritingDay), int> _values = {};

  void put(LibraryId library, NovelId novel, WritingDay day, int delta) {
    _values[(library, novel, day)] = delta;
  }

  @override
  Future<void> addDelta(
    LibraryId libraryId,
    NovelId novelId,
    WritingDay day,
    int delta,
  ) async => put(libraryId, novelId, day, delta);

  @override
  Future<Map<WritingDay, int>> loadDailyDeltas(
    LibraryId libraryId,
    NovelId novelId, {
    required WritingDay fromInclusive,
    required WritingDay toInclusive,
  }) async => _filter(
    _values.entries.where(
      (entry) => entry.key.$1 == libraryId && entry.key.$2 == novelId,
    ),
    fromInclusive,
    toInclusive,
  );

  @override
  Future<Map<WritingDay, int>> loadLibraryDailyDeltas(
    LibraryId libraryId, {
    required WritingDay fromInclusive,
    required WritingDay toInclusive,
  }) async => _filter(
    _values.entries.where((entry) => entry.key.$1 == libraryId),
    fromInclusive,
    toInclusive,
  );

  Map<WritingDay, int> _filter(
    Iterable<MapEntry<(LibraryId, NovelId, WritingDay), int>> entries,
    WritingDay from,
    WritingDay to,
  ) {
    final result = <WritingDay, int>{};
    for (final entry in entries) {
      final day = entry.key.$3;
      if (day.compareTo(from) < 0 || day.compareTo(to) > 0) continue;
      result.update(
        day,
        (value) => value + entry.value,
        ifAbsent: () => entry.value,
      );
    }
    return result;
  }

  @override
  Future<void> pruneBefore(
    LibraryId libraryId,
    WritingDay cutoffExclusive,
  ) async {}
}
