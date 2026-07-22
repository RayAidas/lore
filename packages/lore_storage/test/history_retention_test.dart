import 'package:lore_domain/lore_domain.dart';
import 'package:lore_storage/lore_storage.dart';
import 'package:test/test.dart';

/// 分层时间窗 + 硬上限保留策略的纯函数测试。无需文件 IO。
void main() {
  final now = DateTime.utc(2026, 7, 22, 14, 0);

  HistorySnapshot snap(String id, DateTime createdAt) => HistorySnapshot(
    id: id,
    createdAt: createdAt,
    trigger: HistoryTrigger.autoCheckpoint,
    contentHash: id,
    characterCount: 0,
    isProtected: false,
  );

  test('空列表返回空', () {
    expect(retainAutoSnapshotIds(const [], now), isEmpty);
  });

  test('1 小时内的快照全留', () {
    final ids = retainAutoSnapshotIds([
      snap('a', now.subtract(const Duration(minutes: 5))),
      snap('b', now.subtract(const Duration(minutes: 20))),
      snap('c', now.subtract(const Duration(minutes: 59))),
    ], now);
    expect(ids.toSet(), {'a', 'b', 'c'});
  });

  test('同一小时桶只留最新一条', () {
    // now=14:00；11:59/11:30 距今约 2h → 同一 hour:2 桶；11:00 距今 3h → hour:3 桶。
    final ids = retainAutoSnapshotIds([
      snap('old', now.subtract(const Duration(hours: 3))), // 11:00
      snap('mid', now.subtract(const Duration(hours: 2, minutes: 30))), // 11:30
      snap('new', now.subtract(const Duration(hours: 2, minutes: 1))), // 11:59
    ], now);
    expect(ids.toSet(), {'old', 'new'});
    expect(ids, containsAll(['new', 'old']));
    expect(ids, isNot(contains('mid')));
  });

  test('30 天以上按月分桶只留最新', () {
    final ids = retainAutoSnapshotIds([
      snap('a', now.subtract(const Duration(days: 42))),
      snap('b', now.subtract(const Duration(days: 41))),
      snap('c', now.subtract(const Duration(days: 40))),
    ], now);
    // 40/41/42 天都在 month:1 桶，留最新（40 天）。
    expect(ids, ['c']);
  });

  test('硬上限截断最老的自动快照', () {
    final snaps = [
      for (var i = 0; i < 105; i++)
        snap('s$i', now.subtract(Duration(seconds: i))),
    ];
    final ids = retainAutoSnapshotIds(snaps, now);
    expect(ids, hasLength(historyAutoRetentionLimit));
    // 全在 ≤1h 内（recent 桶全留）→ 截断后保留 createdAt 最大（最新）的 100 条。
    expect(ids.first, 's0');
    expect(ids.last, 's99');
    expect(ids, isNot(contains('s100')));
    expect(ids, isNot(contains('s104')));
  });

  test('跨档组合：各档分别保留最新', () {
    final ids = retainAutoSnapshotIds([
      snap('recent', now.subtract(const Duration(minutes: 10))),
      snap('h-old', now.subtract(const Duration(hours: 3))),
      snap('h-new', now.subtract(const Duration(hours: 2, minutes: 1))),
      snap('day', now.subtract(const Duration(days: 3))),
    ], now);
    // recent 全留；hour:2 桶留 h-new、hour:3 桶留 h-old；day:3 桶留 day。
    expect(ids.toSet(), {'recent', 'h-new', 'h-old', 'day'});
  });

  test('limit 参数可覆盖默认上限', () {
    final snaps = [
      for (var i = 0; i < 10; i++)
        snap('s$i', now.subtract(Duration(seconds: i))),
    ];
    expect(retainAutoSnapshotIds(snaps, now, limit: 3), hasLength(3));
  });
}
