/// 不带时区的用户本地自然日，用于写作统计的日期键。
final class WritingDay implements Comparable<WritingDay> {
  factory WritingDay(int year, int month, int day) {
    if (!_isValidDate(year, month, day)) {
      throw ArgumentError.value(
        '$year-$month-$day',
        'day',
        'Invalid writing day',
      );
    }
    return WritingDay._(year, month, day);
  }

  const WritingDay._(this.year, this.month, this.day);

  factory WritingDay.fromDateTime(DateTime value) =>
      WritingDay(value.year, value.month, value.day);

  factory WritingDay.parse(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) {
      throw FormatException('Invalid writing day: $value');
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    if (!_isValidDate(year, month, day)) {
      throw FormatException('Invalid writing day: $value');
    }
    return WritingDay(year, month, day);
  }

  final int year;
  final int month;
  final int day;

  WritingDay addDays(int value) {
    final next = DateTime.utc(year, month, day).add(Duration(days: value));
    return WritingDay(next.year, next.month, next.day);
  }

  WritingDay get firstDayOfMonth => WritingDay(year, month, 1);

  WritingDay get lastDayOfMonth {
    final nextMonth = DateTime.utc(year, month + 1, 1);
    final last = nextMonth.subtract(const Duration(days: 1));
    return WritingDay(last.year, last.month, last.day);
  }

  String toIso8601String() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  @override
  int compareTo(WritingDay other) {
    final yearComparison = year.compareTo(other.year);
    if (yearComparison != 0) return yearComparison;
    final monthComparison = month.compareTo(other.month);
    if (monthComparison != 0) return monthComparison;
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WritingDay &&
          year == other.year &&
          month == other.month &&
          day == other.day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => toIso8601String();

  static bool _isValidDate(int year, int month, int day) {
    if (year < 1 || year > 9999 || month < 1 || month > 12 || day < 1) {
      return false;
    }
    return day <= DateTime.utc(year, month + 1, 0).day;
  }
}
