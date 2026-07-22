import 'package:lore_domain/lore_domain.dart';

import '../library/library_access.dart';

/// 历史版本端口：枚举、记录、读取、删除与回收某文档的快照。
///
/// 记录（[record]）内部做哈希去重：若正文哈希与该文档最近一条快照相同则跳过，
/// 返回既有快照。回收（[prune]）执行分层时间窗 + 硬上限，受保护（手动）快照
/// 不受影响。恢复语义（留底 + 覆盖）由上层 HistoryService 协调，不在此端口。
abstract interface class HistoryRepository {
  Future<List<HistorySnapshot>> list(
    LibraryAccess access,
    DocumentIdentity doc,
  );

  /// 写入快照（内部哈希去重）。返回实际生效的快照（可能复用最近一条）。
  Future<HistorySnapshot> record(
    LibraryAccess access, {
    required DocumentIdentity doc,
    required String text,
    required HistoryTrigger trigger,
    String? label,
    String? note,
  });

  /// 读取指定快照的正文文本（解压 gzip）。
  Future<String> readSnapshotText(
    LibraryAccess access, {
    required DocumentIdentity doc,
    required String snapshotId,
  });

  Future<void> deleteSnapshot(
    LibraryAccess access, {
    required DocumentIdentity doc,
    required String snapshotId,
  });

  /// 执行分层时间窗 + 硬上限回收，删除被淘汰的自动快照。
  Future<void> prune(LibraryAccess access, DocumentIdentity doc);
}
