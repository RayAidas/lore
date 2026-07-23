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
  static const int historyChangeThreshold = 400;

  /// 定时 autoCheckpoint 安全网快照的间隔（编辑活动期间每此时长留一条）。
  ///
  /// 取 2 分钟：对齐 Obsidian File Recovery 插件默认快照间隔，在「回溯粒度」与
  /// 「版本面板信噪比 / 落盘开销」间取的折中，可按写作反馈再调。
  static const Duration _autoCheckpointInterval = Duration(minutes: 2);

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

  /// 编辑活动期间每 [_autoCheckpointInterval] 留一条 [HistoryTrigger.autoCheckpoint]
  /// 安全网快照，补时间维度的回溯覆盖（与变更量阈值正交）。
  ///
  /// 幂等启动 periodic 定时器：首次编辑活动时启动，之后不重复；内容无变化时由
  /// [_recordHistory] 的哈希去重自动跳过（零垃圾）。定时器挂在文档上，随
  /// [OpenDocument.dispose] 取消，不泄漏。持续写作时保证定期落点；停笔后定时器
  /// 仍在，但去重会让无变化的落盘变 no-op。
  ///
  /// 已知限制：切换走（非关闭）的后台文档定时器仍继续跑，靠去重兜底；编辑过的
  /// 后台文档较多时会有累积的 manifest 读 + hash 开销，留待「失活暂停」优化。
  void scheduleAutoCheckpoint(OpenDocument document) {
    if (historyService == null) return;
    document.historyCheckpointTimer ??= Timer.periodic(
      _autoCheckpointInterval,
      (_) => unawaited(_checkpoint(document)),
    );
  }

  /// 定时落点：取与 [onDocumentSaved]/[onDocumentClosing] 同源的
  /// `document.snapshot.text`（磁盘全文，章节文档含标题行），保证三类自动快照
  /// 哈希去重基线一致、不产生冗余。包 try/catch 与 [_recordHistory] 的 best-effort
  /// 风格对齐：定时器回调可能跨 [OpenDocument.dispose] 执行，避免任何异常外溢。
  Future<void> _checkpoint(OpenDocument document) async {
    try {
      final text = document.snapshot.text;
      await _recordHistory(document, text, HistoryTrigger.autoCheckpoint);
    } catch (_) {
      // best-effort：定时安全网快照失败不影响主流程。
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
