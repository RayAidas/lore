import 'package:lore_domain/lore_domain.dart';

import '../ports/writing_progress_repository.dart';

final class DailyWritingStat {
  const DailyWritingStat({required this.day, required this.netDelta});

  final WritingDay day;
  final int netDelta;
}

final class WritingStatistics {
  const WritingStatistics({
    required this.todayNetDelta,
    required this.weekNetDelta,
    required this.activeDaysThisWeek,
    required this.currentStreakDays,
    required this.monthDays,
  });

  final int todayNetDelta;
  final int weekNetDelta;
  final int activeDaysThisWeek;
  final int currentStreakDays;
  final List<DailyWritingStat> monthDays;
}

/// Calculates reusable library- and novel-level writing statistics.
final class WritingStatisticsService {
  const WritingStatisticsService(this._repository);

  final WritingProgressRepository _repository;

  Future<WritingStatistics> computeLibrary(
    LibraryId libraryId, {
    required WritingDay today,
    WritingDay? month,
  }) => _compute(
    today: today,
    month: month ?? today,
    load: (from, to) => _repository.loadLibraryDailyDeltas(
      libraryId,
      fromInclusive: from,
      toInclusive: to,
    ),
  );

  Future<WritingStatistics> computeNovel(
    LibraryId libraryId,
    NovelId novelId, {
    required WritingDay today,
    WritingDay? month,
  }) => _compute(
    today: today,
    month: month ?? today,
    load: (from, to) => _repository.loadDailyDeltas(
      libraryId,
      novelId,
      fromInclusive: from,
      toInclusive: to,
    ),
  );

  Future<WritingStatistics> _compute({
    required WritingDay today,
    required WritingDay month,
    required Future<Map<WritingDay, int>> Function(WritingDay, WritingDay) load,
  }) async {
    final monthStart = month.firstDayOfMonth;
    final monthEnd = month.lastDayOfMonth;
    final weekStart = today.addDays(1 - _weekday(today));
    final historyStart = today.addDays(-364);
    // The calendar may display any month, but the summary always describes
    // the current day and week. Query the union so changing month cannot turn
    // today's metrics into zero merely because its data was not loaded.
    final from = historyStart.compareTo(monthStart) < 0
        ? historyStart
        : monthStart;
    final to = monthEnd.compareTo(today) > 0 ? monthEnd : today;
    final deltas = await load(from, to);
    final weekEnd = weekStart.addDays(6);
    final weekDays = _days(weekStart, weekEnd);
    final monthDays = _days(monthStart, monthEnd)
        .map((day) => DailyWritingStat(day: day, netDelta: deltas[day] ?? 0))
        .toList(growable: false);
    var streak = 0;
    for (
      var day = today;
      day.compareTo(historyStart) >= 0;
      day = day.addDays(-1)
    ) {
      if ((deltas[day] ?? 0) <= 0) break;
      streak++;
    }
    return WritingStatistics(
      todayNetDelta: deltas[today] ?? 0,
      weekNetDelta: weekDays.fold(0, (sum, day) => sum + (deltas[day] ?? 0)),
      activeDaysThisWeek: weekDays
          .where((day) => (deltas[day] ?? 0) > 0)
          .length,
      currentStreakDays: streak,
      monthDays: monthDays,
    );
  }

  int _weekday(WritingDay day) =>
      DateTime.utc(day.year, day.month, day.day).weekday;

  Iterable<WritingDay> _days(WritingDay from, WritingDay to) sync* {
    for (var day = from; day.compareTo(to) <= 0; day = day.addDays(1)) {
      yield day;
    }
  }
}
