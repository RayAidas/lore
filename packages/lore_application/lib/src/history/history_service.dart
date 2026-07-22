import 'package:lore_domain/lore_domain.dart';

import '../library/library_access.dart';
import '../ports/document_repository.dart';
import '../ports/history_repository.dart';

sealed class RestoreResult {
  const RestoreResult();
}

final class RestoreSuccess extends RestoreResult {
  const RestoreSuccess(this.snapshot);

  /// 恢复后写回磁盘的新快照（含新 revision）。
  final DocumentSnapshot snapshot;
}

/// 磁盘在外部被修改，恢复未能覆盖。上层应提示用户先处理外部冲突。
final class RestoreConflict extends RestoreResult {
  const RestoreConflict(this.diskSnapshot);

  final DocumentSnapshot diskSnapshot;
}

/// 历史版本的协调用例：在 [HistoryRepository] 之上封装恢复语义（留底 + 覆盖）
/// 与触发入口。
///
/// 变更量阈值计数由编辑器 / workspace 维护，达到阈值时调用 [recordAuto]；
/// 本服务无状态，不持有编辑会话。
class HistoryService {
  HistoryService({
    required HistoryRepository historyRepository,
    required DocumentRepository documentRepository,
  }) : _history = historyRepository,
       _documents = documentRepository;

  final HistoryRepository _history;
  final DocumentRepository _documents;

  Future<List<HistorySnapshot>> list(
    LibraryAccess access,
    DocumentIdentity doc,
  ) => _history.list(access, doc);

  /// 用户主动创建命名版本（永久保留）。
  Future<HistorySnapshot> createVersion(
    LibraryAccess access, {
    required DocumentIdentity doc,
    required String text,
    String? label,
    String? note,
  }) => _history.record(
    access,
    doc: doc,
    text: text,
    trigger: HistoryTrigger.manual,
    label: label,
    note: note,
  );

  /// 自动留档（checkpoint / threshold）。触发时机由调用方决定。
  Future<HistorySnapshot> recordAuto(
    LibraryAccess access, {
    required DocumentIdentity doc,
    required String text,
    required HistoryTrigger trigger,
  }) => _history.record(access, doc: doc, text: text, trigger: trigger);

  Future<String> readSnapshotText(
    LibraryAccess access, {
    required DocumentIdentity doc,
    required String snapshotId,
  }) => _history.readSnapshotText(access, doc: doc, snapshotId: snapshotId);

  Future<void> deleteSnapshot(
    LibraryAccess access, {
    required DocumentIdentity doc,
    required String snapshotId,
  }) => _history.deleteSnapshot(access, doc: doc, snapshotId: snapshotId);

  Future<void> prune(LibraryAccess access, DocumentIdentity doc) =>
      _history.prune(access, doc);

  /// 恢复某历史版本：先为当前磁盘内容留底（restoreSafeguard），再用快照文本
  /// 覆盖磁盘。当前内容与目标相同时不留底。磁盘被外部修改时返回
  /// [RestoreConflict]，由上层提示用户，不自动强覆盖。
  ///
  /// 已知窗口：留底保存的是 readDocument 时刻的磁盘内容，与随后 saveDocument
  /// 之间存在 read-modify-write 间隔；极端并发下留底可能是中间态。这是固有
  /// 取舍——换取「覆盖失败也留底」的可靠性。
  Future<RestoreResult> restore(
    LibraryAccess access, {
    required DocumentIdentity doc,
    required String snapshotId,
  }) async {
    final targetText = await _history.readSnapshotText(
      access,
      doc: doc,
      snapshotId: snapshotId,
    );
    final ref = DocumentRef(relativePath: doc.relativePath, format: doc.format);
    final current = await _documents.readDocument(access, ref);
    if (current.text != targetText) {
      await _history.record(
        access,
        doc: doc,
        text: current.text,
        trigger: HistoryTrigger.restoreSafeguard,
      );
    }
    final result = await _documents.saveDocument(
      access,
      original: current,
      text: targetText,
    );
    return switch (result) {
      DocumentSaveSuccess(:final snapshot) => RestoreSuccess(snapshot),
      DocumentSaveConflict(:final diskSnapshot) => RestoreConflict(
        diskSnapshot,
      ),
    };
  }
}
