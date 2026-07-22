import 'package:flutter_test/flutter_test.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_platform_adapters/lore_platform_adapters.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const libraryId = LibraryId('library-a');
  const otherLibraryId = LibraryId('library-b');
  const novelId = NovelId('11111111-1111-4111-8111-111111111111');
  const otherNovelId = NovelId('22222222-2222-4222-8222-222222222222');
  final day = WritingDay(2026, 7, 17);
  late SharedPreferencesWritingProgressRepository repository;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repository = SharedPreferencesWritingProgressRepository();
  });

  test('accumulates scoped daily deltas and supports range queries', () async {
    await repository.addDelta(libraryId, novelId, day, 120);
    await repository.addDelta(libraryId, novelId, day, -20);
    final values = await repository.loadDailyDeltas(
      libraryId,
      novelId,
      fromInclusive: day,
      toInclusive: day,
    );
    expect(values, {day: 100});
  });

  test('aggregates only novels in the requested library', () async {
    await repository.addDelta(libraryId, novelId, day, 100);
    await repository.addDelta(libraryId, otherNovelId, day, 50);
    await repository.addDelta(otherLibraryId, novelId, day, 900);
    final values = await repository.loadLibraryDailyDeltas(
      libraryId,
      fromInclusive: day,
      toInclusive: day,
    );
    expect(values, {day: 150});
  });

  test('migrates legacy v1 counts on first read', () async {
    SharedPreferences.setMockInitialValues({
      'lore.writing.progress.${novelId.value}':
          '{"schemaVersion":1,"counts":{"2026-07-17":80}}',
    });
    repository = SharedPreferencesWritingProgressRepository();
    final values = await repository.loadDailyDeltas(
      libraryId,
      novelId,
      fromInclusive: day,
      toInclusive: day,
    );
    expect(values, {day: 80});
  });

  test(
    'does not assign legacy data to an arbitrary library aggregate',
    () async {
      SharedPreferences.setMockInitialValues({
        'lore.writing.progress.${novelId.value}':
            '{"schemaVersion":1,"counts":{"2026-07-17":80}}',
      });
      repository = SharedPreferencesWritingProgressRepository();
      final values = await repository.loadLibraryDailyDeltas(
        libraryId,
        fromInclusive: day,
        toInclusive: day,
      );
      expect(values, isEmpty);
    },
  );

  test('prunes old records without changing newer ones', () async {
    await repository.addDelta(libraryId, novelId, WritingDay(2026, 6, 1), 100);
    await repository.addDelta(libraryId, novelId, day, 200);
    await repository.pruneBefore(libraryId, WritingDay(2026, 7, 1));
    final values = await repository.loadDailyDeltas(
      libraryId,
      novelId,
      fromInclusive: WritingDay(2026, 1, 1),
      toInclusive: day,
    );
    expect(values, {day: 200});
  });

  test('survives corrupted JSON and serializes concurrent writes', () async {
    SharedPreferences.setMockInitialValues({
      'lore.writing.progress.${libraryId.value}.${novelId.value}': '{bad',
    });
    repository = SharedPreferencesWritingProgressRepository();
    await Future.wait(
      List.generate(
        10,
        (_) => repository.addDelta(libraryId, novelId, day, 10),
      ),
    );
    final values = await repository.loadDailyDeltas(
      libraryId,
      novelId,
      fromInclusive: day,
      toInclusive: day,
    );
    expect(values, {day: 100});
  });
}
