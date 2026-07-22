// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';

import 'history_change_magnitude.dart';
import 'history_diff_mode.dart';
import 'workspace_document.dart';

/// diff 对比目标：当前在中间区展示的「某历史快照 vs 当前磁盘」对比。
final class HistoryDiffTarget {
  const HistoryDiffTarget({
    required this.relativePath,
    required this.snapshotId,
    required this.snapshotText,
    required this.snapshotTitle,
  });

  final String relativePath;
  final String snapshotId;

  /// 已加载的历史快照正文（diff 的「旧」一侧）。
  final String snapshotText;

  /// 工具条显示的快照标题（时间 + 可选命名）。
  final String snapshotTitle;
}

/// 工作区历史版本与 diff 视图状态：跨历史服务（[HistoryService]）记录自动快照、
/// 提供版本面板的增删改查入口，并维护「某历史快照 vs 当前磁盘」的 diff 对比态。
///
/// 不持有 ChangeNotifier、不自行 notify——状态变更通过构造时注入的 [notify]
/// 回调触发 [WorkspaceController] 整体 notifyListeners。跨 store 协作（判断文档
/// 是否仍打开、按路径取打开文档、恢复后重载编辑器、按路径查章节节点）同样由
/// 注入的回调表达，与 [WorkspaceTabsStore] 注入 `novelIdForPath` 同构。
final class WorkspaceHistoryStore {
  WorkspaceHistoryStore({
    required this.session,
    required this.historyService,
    required void Function() notify,
    required bool Function(OpenDocument document) isOpenDocument,
    required OpenDocument? Function(String relativePath) openDocumentByPath,
    required Future<void> Function(OpenDocument document)
    reloadDocumentFromDisk,
    required String? Function(String relativePath) chapterNodeIdForPath,
  }) : _notify = notify,
       _isOpenDocument = isOpenDocument,
       _openDocumentByPath = openDocumentByPath,
       _reloadDocumentFromDisk = reloadDocumentFromDisk,
       _chapterNodeIdForPath = chapterNodeIdForPath;

  final LibrarySession session;
  final HistoryService? historyService;

  final void Function() _notify;
  final bool Function(OpenDocument) _isOpenDocument;
  final OpenDocument? Function(String) _openDocumentByPath;
  final Future<void> Function(OpenDocument) _reloadDocumentFromDisk;
  final String? Function(String) _chapterNodeIdForPath;

  /// 历史快照变更量阈值（自上次快照后的近似净变更字符数）。
  static const int historyChangeThreshold = 800;

  /// 当前 diff 对比目标（点版本列表项时设置，退出 diff 时清空）。
  HistoryDiffTarget? _diffTarget;
  DiffViewMode _diffMode = DiffViewMode.inline;

  /// showHistoryDiff 的序列号：丢弃加载期间被取代的过期结果。
  int _showDiffGen = 0;

  DocumentIdentity _identityFor(OpenDocument document) {
    return DocumentIdentity(
      nodeId: _chapterNodeIdForPath(document.relativePath),
      relativePath: document.relativePath,
      format: document.format,
    );
  }

  // --- 快照写入（注入给 WorkspaceTabsStore 的回调） ---

  /// 保存成功后判定变更量阈值，达阈值则记录自动快照（threshold）。
  void onDocumentSaved(OpenDocument document) {
    final history = historyService;
    if (history == null) return;
    final text = document.snapshot.text;
    final last = document.lastHistorySnapshotText;
    final magnitude = last == null
        ? text.length
        : historyChangeMagnitude(last, text);
    if (last == null || magnitude >= historyChangeThreshold) {
      unawaited(_recordHistory(document, text, HistoryTrigger.autoThreshold));
    }
  }

  /// 文档关闭前为当前内容留 checkpoint（与上次快照不同才记）。
  Future<void> onDocumentClosing(OpenDocument document) async {
    final history = historyService;
    if (history == null) return;
    final text = document.snapshot.text;
    if (document.lastHistorySnapshotText != text) {
      await _recordHistory(document, text, HistoryTrigger.autoCheckpoint);
    }
  }

  Future<void> _recordHistory(
    OpenDocument document,
    String text,
    HistoryTrigger trigger,
  ) async {
    final history = historyService;
    if (history == null) return;
    final identity = _identityFor(document);
    try {
      await history.recordAuto(
        session.access,
        doc: identity,
        text: text,
        trigger: trigger,
      );
      if (_isOpenDocument(document)) {
        document.lastHistorySnapshotText = text;
      }
      unawaited(history.prune(session.access, identity));
    } catch (_) {
      // 历史记录是 best-effort，失败不影响主流程。
    }
  }

  // --- 历史版本：面板入口 ---

  DocumentIdentity? historyIdentityFor(OpenDocument document) {
    if (historyService == null) return null;
    return _identityFor(document);
  }

  Future<List<HistorySnapshot>> listHistorySnapshots(
    DocumentIdentity identity,
  ) {
    final history = historyService;
    if (history == null) return Future.value(const <HistorySnapshot>[]);
    return history.list(session.access, identity);
  }

  Future<HistorySnapshot> createHistoryVersion(
    DocumentIdentity identity,
    String text, {
    String? label,
    String? note,
  }) {
    return historyService!.createVersion(
      session.access,
      doc: identity,
      text: text,
      label: label,
      note: note,
    );
  }

  Future<void> deleteHistorySnapshot(
    DocumentIdentity identity,
    String snapshotId,
  ) {
    return historyService!.deleteSnapshot(
      session.access,
      doc: identity,
      snapshotId: snapshotId,
    );
  }

  /// 恢复历史版本：留底 + 覆盖磁盘 + 重载编辑器。
  Future<RestoreResult> restoreHistorySnapshot(
    DocumentIdentity identity,
    String snapshotId,
  ) async {
    final history = historyService;
    final result = await history!.restore(
      session.access,
      doc: identity,
      snapshotId: snapshotId,
    );
    if (result is RestoreSuccess) {
      _diffTarget = null;
      final document = _openDocumentByPath(identity.relativePath);
      if (document != null) {
        await _reloadDocumentFromDisk(document);
        document.lastHistorySnapshotText = result.snapshot.text;
      }
    }
    return result;
  }

  // --- 历史版本：diff 视图（替换编辑器） ---

  HistoryDiffTarget? get diffTarget => _diffTarget;

  DiffViewMode get diffMode => _diffMode;

  bool isDiffing(OpenDocument document) =>
      _diffTarget != null && _diffTarget!.relativePath == document.relativePath;

  /// 点版本列表项：加载该快照文本，进入 diff（替换编辑器视图）。
  Future<void> showHistoryDiff(
    OpenDocument document,
    HistorySnapshot snapshot,
  ) async {
    final history = historyService;
    if (history == null) return;
    final gen = ++_showDiffGen;
    final identity = _identityFor(document);
    try {
      final text = await history.readSnapshotText(
        session.access,
        doc: identity,
        snapshotId: snapshot.id,
      );
      // 加载期间若用户点了别的版本或退出 diff，丢弃本次过期结果。
      if (gen != _showDiffGen) return;
      _diffTarget = HistoryDiffTarget(
        relativePath: document.relativePath,
        snapshotId: snapshot.id,
        snapshotText: text,
        snapshotTitle: _formatSnapshotTitle(snapshot),
      );
      _notify();
    } catch (_) {
      // best-effort：加载失败静默放弃，不影响主流程。
    }
  }

  void exitHistoryDiff() {
    _showDiffGen += 1; // 使进行中的 showHistoryDiff 失效。
    if (_diffTarget == null) return;
    _diffTarget = null;
    _notify();
  }

  void setDiffMode(DiffViewMode mode) {
    if (_diffMode == mode) return;
    _diffMode = mode;
    _notify();
  }

  String _formatSnapshotTitle(HistorySnapshot snapshot) {
    final time = _formatHistoryTime(snapshot.createdAt);
    final label = snapshot.label;
    return label == null ? time : '$time · $label';
  }

  String _formatHistoryTime(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
