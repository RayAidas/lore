import 'package:lore_domain/lore_domain.dart';

/// 自动快照的硬上限（防御性兜底）。分层时间窗稳态约 50 条，高峰约 60–80，
/// 100 给足缓冲；正常永不触发。
const int historyAutoRetentionLimit = 100;

/// 计算自动快照经分层时间窗 + 硬上限后应保留的 id（按 createdAt 降序）。
///
/// 纯函数，便于直接测试；受保护（手动）快照不传入此函数，由调用方豁免。
/// 算法：快照按时间降序遍历，每个时间窗桶只保留最先遇到（即最新）的一条；
/// 最后若超过 [limit]，截断保留最新的 [limit] 条。
List<String> retainAutoSnapshotIds(
  List<HistorySnapshot> autoSnapshots,
  DateTime now, {
  int limit = historyAutoRetentionLimit,
}) {
  final sorted = List<HistorySnapshot>.of(autoSnapshots)
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final seen = <String>{};
  final kept = <HistorySnapshot>[];
  for (final snapshot in sorted) {
    final age = now.difference(snapshot.createdAt);
    if (seen.add(historyRetentionBucket(age, snapshot.createdAt))) {
      kept.add(snapshot);
    }
  }
  if (kept.length > limit) {
    kept.removeRange(limit, kept.length);
  }
  return kept.map((snapshot) => snapshot.id).toList();
}

/// 分层时间窗桶键（近细远疏）。
///
/// [age] 应由 UTC 时刻相减得到（[createdAt] 已 `toUtc()`，
/// [retainAutoSnapshotIds] 的 `now` 来自 `clock.nowUtc()`），避免本地时
/// DST 偏移污染差值。
/// - < 61 分钟：每条独占桶（全留，含恰好 60 分整的边界）；
/// - 1–24 小时：按小时分桶；
/// - 1–7 天：按天分桶；
/// - 7–30 天：按周分桶；
/// - >30 天：按月分桶。
String historyRetentionBucket(Duration age, DateTime createdAt) {
  if (age.inMinutes <= 60) {
    return 'recent:${createdAt.toIso8601String()}';
  }
  if (age.inHours <= 24) {
    return 'hour:${age.inHours}';
  }
  if (age.inDays <= 7) {
    return 'day:${age.inDays}';
  }
  if (age.inDays <= 30) {
    return 'week:${age.inDays ~/ 7}';
  }
  return 'month:${age.inDays ~/ 30}';
}
