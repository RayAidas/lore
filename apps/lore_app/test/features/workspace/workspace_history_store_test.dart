import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_app/features/workspace/workspace_document.dart';
import 'package:lore_app/features/workspace/workspace_history_store.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_editor/lore_editor.dart';

final _session = LibrarySession(
  access: const LibraryAccess(
    token: '/tmp/library',
    displayPath: '/tmp/library',
    isPending: false,
  ),
  metadata: LibraryMetadata(
    schemaVersion: 1,
    id: const LibraryId('11111111-1111-4111-8111-111111111111'),
    createdAt: DateTime.utc(2026, 7, 17),
    updatedAt: DateTime.utc(2026, 7, 17),
  ),
);

HistorySnapshot _snapshot(String id) => HistorySnapshot(
  id: id,
  createdAt: DateTime.utc(2026, 7, 17, 9),
  trigger: HistoryTrigger.manual,
  contentHash: 'hash-$id',
  characterCount: 0,
  isProtected: false,
);

/// 构造一个可独立使用的 [OpenDocument]。散文件（无 nodeId），editor/scroll
/// controller 随 teardown 释放。
OpenDocument _document({
  required String text,
  String? lastHistorySnapshotText,
  String path = '散文件.txt',
}) {
  final editor = LoreTextController(text: text);
  final scroll = ScrollController();
  addTearDown(editor.dispose);
  addTearDown(scroll.dispose);
  final doc = OpenDocument(
    snapshot: DocumentSnapshot(
      ref: DocumentRef(relativePath: path, format: DocumentFormat.text),
      text: text,
      encoding: TextEncoding.utf8,
      lineEnding: LineEnding.lf,
      revision: DocumentRevision('rev-1'),
    ),
    editorController: editor,
    scrollController: scroll,
  );
  doc.lastHistorySnapshotText = lastHistorySnapshotText;
  return doc;
}

WorkspaceHistoryStore _store(_FakeHistoryService fake) => WorkspaceHistoryStore(
  session: _session,
  historyService: fake,
  notify: () {},
  isOpenDocument: (_) => true,
  openDocumentByPath: (_) => null,
  reloadDocumentFromDisk: (_) async {},
  chapterNodeIdForPath: (_) => null,
);

/// 刷新若干轮 microtask，让 `unawaited(_recordHistory(...))` 的异步链跑完。
Future<void> _flush() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  // --- onDocumentSaved 阈值判定 ---

  test('onDocumentSaved records on first save regardless of size', () async {
    final fake = _FakeHistoryService();
    final store = _store(fake);

    // last==null（首次）：短路条件成立，无论字数都留 threshold 快照。
    store.onDocumentSaved(_document(text: '短'));
    await _flush();

    expect(fake.recordAutoCalls, hasLength(1));
    expect(fake.recordAutoCalls.single.trigger, HistoryTrigger.autoThreshold);
  });

  test(
    'onDocumentSaved skips when change magnitude is below threshold',
    () async {
      final fake = _FakeHistoryService();
      final store = _store(fake);
      // historyChangeMagnitude：公共前缀 50、尾部仅 +1 → magnitude = 1 < 800。
      final doc = _document(
        text: 'a' * 50 + 'b',
        lastHistorySnapshotText: 'a' * 50,
      );

      store.onDocumentSaved(doc);
      await _flush();

      expect(fake.recordAutoCalls, isEmpty);
    },
  );

  test(
    'onDocumentSaved records when change magnitude reaches threshold',
    () async {
      final fake = _FakeHistoryService();
      final store = _store(fake);
      // historyChangeMagnitude：prefix=1、suffix=0 → magnitude = 0 + 900 = 900 ≥ 800。
      final newText = 'a${'b' * 900}';
      final doc = _document(text: newText, lastHistorySnapshotText: 'a');

      store.onDocumentSaved(doc);
      await _flush();

      expect(fake.recordAutoCalls, hasLength(1));
      expect(fake.recordAutoCalls.single.trigger, HistoryTrigger.autoThreshold);
      // 保存后回写 lastHistorySnapshotText（isOpenDocument 回调返回 true）。
      expect(doc.lastHistorySnapshotText, newText);
    },
  );

  // --- onDocumentClosing checkpoint ---

  test(
    'onDocumentClosing leaves no checkpoint when content unchanged',
    () async {
      final fake = _FakeHistoryService();
      final store = _store(fake);
      final doc = _document(text: '不变', lastHistorySnapshotText: '不变');

      await store.onDocumentClosing(doc);

      expect(fake.recordAutoCalls, isEmpty);
    },
  );

  test('onDocumentClosing leaves checkpoint when content changed', () async {
    final fake = _FakeHistoryService();
    final store = _store(fake);
    final doc = _document(text: '新内容', lastHistorySnapshotText: '旧');

    await store.onDocumentClosing(doc);

    expect(fake.recordAutoCalls, hasLength(1));
    expect(fake.recordAutoCalls.single.trigger, HistoryTrigger.autoCheckpoint);
  });

  // --- showHistoryDiff 并发序号丢弃 ---

  test(
    'showHistoryDiff discards stale result when a newer diff is requested',
    () async {
      final stale = Completer<String>();
      final fake = _FakeHistoryService(
        readOverrides: {
          'snap-old': stale.future,
          'snap-new': Future.value('新快照正文'),
        },
      );
      final store = _store(fake);
      final doc = _document(text: '当前正文');

      // 第一次：readSnapshotText 挂起在未完成的 Completer 上。
      unawaited(store.showHistoryDiff(doc, _snapshot('snap-old')));
      await _flush();

      // 第二次：立即完成 → diffTarget 指向 snap-new。
      await store.showHistoryDiff(doc, _snapshot('snap-new'));
      expect(store.diffTarget, isNotNull);
      expect(store.diffTarget!.snapshotId, 'snap-new');

      // 放行第一次：其 gen 已被第二次超越，结果丢弃，diffTarget 仍是 snap-new。
      stale.complete('旧快照正文');
      await _flush();

      expect(store.diffTarget!.snapshotId, 'snap-new');
    },
  );
}

class _RecordAutoCall {
  const _RecordAutoCall(this.doc, this.text, this.trigger);

  final DocumentIdentity doc;
  final String text;
  final HistoryTrigger trigger;
}

/// 记录调用、返回可控结果的 [HistoryService] 替身。
class _FakeHistoryService implements HistoryService {
  _FakeHistoryService({Map<String, Future<String>>? readOverrides})
    : readOverrides = readOverrides ?? const {};

  final List<_RecordAutoCall> recordAutoCalls = [];
  final Map<String, Future<String>> readOverrides;

  @override
  Future<HistorySnapshot> recordAuto(
    LibraryAccess access, {
    required DocumentIdentity doc,
    required String text,
    required HistoryTrigger trigger,
  }) async {
    recordAutoCalls.add(_RecordAutoCall(doc, text, trigger));
    return _snapshot('auto-${recordAutoCalls.length}');
  }

  @override
  Future<String> readSnapshotText(
    LibraryAccess access, {
    required DocumentIdentity doc,
    required String snapshotId,
  }) => readOverrides[snapshotId] ?? Future.value('snap-text');

  @override
  Future<List<HistorySnapshot>> list(
    LibraryAccess access,
    DocumentIdentity doc,
  ) => Future.value(const <HistorySnapshot>[]);

  @override
  Future<HistorySnapshot> createVersion(
    LibraryAccess access, {
    required DocumentIdentity doc,
    required String text,
    String? label,
    String? note,
  }) => Future.value(_snapshot('manual'));

  @override
  Future<void> deleteSnapshot(
    LibraryAccess access, {
    required DocumentIdentity doc,
    required String snapshotId,
  }) => Future.value();

  @override
  Future<void> prune(LibraryAccess access, DocumentIdentity doc) =>
      Future.value();

  @override
  Future<RestoreResult> restore(
    LibraryAccess access, {
    required DocumentIdentity doc,
    required String snapshotId,
  }) => throw UnimplementedError();
}
