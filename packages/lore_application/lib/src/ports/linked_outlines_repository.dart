import 'package:lore_domain/lore_domain.dart';

/// 每部小说关联大纲路径的设备本地持久化端口。
///
/// 按小说（novelId）记住关联选择，重启不丢。实现写入可重建的本地存储
/// （如 SharedPreferences），[load] 返回 `null` 表示从未保存过。
abstract interface class LinkedOutlinesRepository {
  Future<NovelOutlineLinks?> load();

  Future<void> save(NovelOutlineLinks links);
}
