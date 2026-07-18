import 'package:flutter_test/flutter_test.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_storage/lore_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const novelId = NovelId('11111111-1111-4111-8111-111111111111');
  late SharedPreferencesWritingProgressRepository repository;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repository = SharedPreferencesWritingProgressRepository();
  });

  test('returns zero when no entry for today', () async {
    expect(await repository.loadToday(novelId, DateTime.utc(2026, 7, 17)), 0);
  });

  test('accumulates deltas within the same UTC day', () async {
    final day = DateTime.utc(2026, 7, 17);
    await repository.addDelta(novelId, day, 120);
    await repository.addDelta(novelId, day, 80);
    expect(await repository.loadToday(novelId, day), 200);
  });

  test('separates counts across UTC date boundary', () async {
    await repository.addDelta(novelId, DateTime.utc(2026, 7, 17, 23, 59), 100);
    await repository.addDelta(novelId, DateTime.utc(2026, 7, 18, 0, 1), 50);
    expect(await repository.loadToday(novelId, DateTime.utc(2026, 7, 17)), 100);
    expect(await repository.loadToday(novelId, DateTime.utc(2026, 7, 18)), 50);
  });

  test('ignores zero deltas', () async {
    final day = DateTime.utc(2026, 7, 17);
    await repository.addDelta(novelId, day, 0);
    expect(await repository.loadToday(novelId, day), 0);
  });

  test('pruneBefore removes old entries and keeps newer', () async {
    await repository.addDelta(novelId, DateTime.utc(2026, 6, 1), 100);
    await repository.addDelta(novelId, DateTime.utc(2026, 7, 17), 200);
    await repository.pruneBefore(DateTime.utc(2026, 7, 1));
    expect(await repository.loadToday(novelId, DateTime.utc(2026, 6, 1)), 0);
    expect(await repository.loadToday(novelId, DateTime.utc(2026, 7, 17)), 200);
  });

  test('survives corrupted JSON by treating as empty', () async {
    SharedPreferences.setMockInitialValues({
      'lore.writing.progress.${novelId.value}': '{bad',
    });
    expect(await repository.loadToday(novelId, DateTime.utc(2026, 7, 17)), 0);
    await repository.addDelta(novelId, DateTime.utc(2026, 7, 17), 30);
    expect(await repository.loadToday(novelId, DateTime.utc(2026, 7, 17)), 30);
  });

  test('serializes concurrent addDelta without losing increments', () async {
    final day = DateTime.utc(2026, 7, 17);
    // 10 个并发 addDelta 各 +10，串行化后总和应为 100（无覆盖丢失）。
    await Future.wait(
      List.generate(10, (_) => repository.addDelta(novelId, day, 10)),
    );
    expect(await repository.loadToday(novelId, day), 100);
  });
}
