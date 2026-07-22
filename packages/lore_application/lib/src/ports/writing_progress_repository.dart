import 'package:lore_domain/lore_domain.dart';

/// 写作进度的设备本地持久化端口。
///
/// 数据按书库与小说隔离，日期键使用用户本地自然日。它是可重建的派生统计，
/// 不属于权威内容，不应随书库迁移。
abstract interface class WritingProgressRepository {
  Future<Map<WritingDay, int>> loadDailyDeltas(
    LibraryId libraryId,
    NovelId novelId, {
    required WritingDay fromInclusive,
    required WritingDay toInclusive,
  });

  Future<Map<WritingDay, int>> loadLibraryDailyDeltas(
    LibraryId libraryId, {
    required WritingDay fromInclusive,
    required WritingDay toInclusive,
  });

  Future<void> addDelta(
    LibraryId libraryId,
    NovelId novelId,
    WritingDay day,
    int delta,
  );

  /// 清理当前书库在 [cutoffExclusive] 之前的记录。
  Future<void> pruneBefore(LibraryId libraryId, WritingDay cutoffExclusive);
}
