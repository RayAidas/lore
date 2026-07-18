import 'package:lore_domain/lore_domain.dart';

/// 写作进度（今日字数等）的持久化端口。
///
/// 日期键统一使用 UTC，避免跨时区导致"今日"边界漂移。数据为可重建的派生
/// 统计，不属于权威内容，不应随书库迁移。
abstract interface class WritingProgressRepository {
  Future<int> loadToday(NovelId novelId, DateTime todayUtc);

  Future<void> addDelta(NovelId novelId, DateTime todayUtc, int delta);

  /// 清理所有小说在 [cutoffUtc] 之前的记录。
  Future<void> pruneBefore(DateTime cutoffUtc);
}
