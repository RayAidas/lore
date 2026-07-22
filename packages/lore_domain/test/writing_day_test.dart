import 'package:lore_domain/lore_domain.dart';
import 'package:test/test.dart';

void main() {
  test('encodes, parses, and orders ISO calendar days', () {
    final day = WritingDay(2026, 7, 3);
    expect(day.toIso8601String(), '2026-07-03');
    expect(WritingDay.parse('2026-07-03'), day);
    expect(day.compareTo(WritingDay(2026, 7, 4)), lessThan(0));
  });

  test('rejects invalid calendar days', () {
    expect(() => WritingDay.parse('2026-02-29'), throwsFormatException);
    expect(() => WritingDay.parse('2026/07/03'), throwsFormatException);
  });

  test('crosses month boundaries when adding days', () {
    expect(WritingDay(2026, 1, 31).addDays(1), WritingDay(2026, 2, 1));
    expect(WritingDay(2024, 2, 29).addDays(1), WritingDay(2024, 3, 1));
    expect(WritingDay(2026, 2, 10).lastDayOfMonth, WritingDay(2026, 2, 28));
  });
}
