import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:test/test.dart';

/// HistoryService 协调逻辑测试：用内存 fake repositories 隔离存储与文档 IO，
/// 聚焦恢复的留底 + 覆盖 + 冲突语义。
void main() {
  late _FakeHistory history;
  late _FakeDocuments documents;
  late HistoryService service;
  final access = LibraryAccess(
    token: 'lib',
    displayPath: 'lib',
    isPending: false,
  );

  const doc = DocumentIdentity(
    nodeId: 'chapter-1',
    relativePath: '正文/第1章.md',
    format: DocumentFormat.markdown,
  );

  setUp(() {
    history = _FakeHistory();
    documents = _FakeDocuments();
    service = HistoryService(
      historyRepository: history,
      documentRepository: documents,
    );
  });

  test('恢复时为当前内容留底并覆盖磁盘', () async {
    documents.seed(doc.relativePath, '当前内容A', revision: 'r1');
    final target = await history.record(
      access,
      doc: doc,
      text: '历史版本B',
      trigger: HistoryTrigger.autoCheckpoint,
    );

    final result = await service.restore(
      access,
      doc: doc,
      snapshotId: target.id,
    );

    expect(result, isA<RestoreSuccess>());
    expect(documents.textOf(doc.relativePath), '历史版本B');
    // 留底：history 应含一条 restoreSafeguard（当前内容A）。
    final snaps = await service.list(access, doc);
    final safeguard = snaps.where(
      (s) => s.trigger == HistoryTrigger.restoreSafeguard,
    );
    expect(safeguard, hasLength(1));
    expect(
      await service.readSnapshotText(
        access,
        doc: doc,
        snapshotId: safeguard.single.id,
      ),
      '当前内容A',
    );
  });

  test('当前内容与目标相同时不留底', () async {
    documents.seed(doc.relativePath, '相同', revision: 'r1');
    final target = await history.record(
      access,
      doc: doc,
      text: '相同',
      trigger: HistoryTrigger.autoCheckpoint,
    );

    await service.restore(access, doc: doc, snapshotId: target.id);

    final snaps = await service.list(access, doc);
    expect(
      snaps.every((s) => s.trigger != HistoryTrigger.restoreSafeguard),
      isTrue,
    );
    expect(documents.textOf(doc.relativePath), '相同');
  });

  test('磁盘被外部修改时返回冲突，不覆盖', () async {
    documents.seed(doc.relativePath, '当前', revision: 'r1');
    final target = await history.record(
      access,
      doc: doc,
      text: '目标',
      trigger: HistoryTrigger.autoCheckpoint,
    );
    documents.forceConflict = true;

    final result = await service.restore(
      access,
      doc: doc,
      snapshotId: target.id,
    );

    expect(result, isA<RestoreConflict>());
    // 留底仍应执行（恢复前先留底，与覆盖是否冲突无关）。
    final snaps = await service.list(access, doc);
    expect(
      snaps.any((s) => s.trigger == HistoryTrigger.restoreSafeguard),
      isTrue,
    );
  });

  test('createVersion 写入手动版本并带命名', () async {
    final snap = await service.createVersion(
      access,
      doc: doc,
      text: '交稿',
      label: '交稿前',
      note: '备注',
    );
    expect(snap.trigger, HistoryTrigger.manual);
    expect(snap.isProtected, isTrue);
    expect(snap.label, '交稿前');
  });
}

final class _FakeHistory implements HistoryRepository {
  final Map<String, List<({HistorySnapshot snapshot, String text})>> _store =
      {};
  var _id = 0;

  @override
  Future<List<HistorySnapshot>> list(
    LibraryAccess access,
    DocumentIdentity doc,
  ) async {
    final entries = _store[doc.logicalKey] ?? const [];
    return entries.map((e) => e.snapshot).toList();
  }

  @override
  Future<HistorySnapshot> record(
    LibraryAccess access, {
    required DocumentIdentity doc,
    required String text,
    required HistoryTrigger trigger,
    String? label,
    String? note,
  }) async {
    final list = _store.putIfAbsent(doc.logicalKey, () => []);
    if (list.isNotEmpty && list.last.text == text) {
      return list.last.snapshot;
    }
    _id += 1;
    final isManual = trigger == HistoryTrigger.manual;
    final snap = HistorySnapshot(
      id: 'snap-$_id',
      createdAt: DateTime.utc(2026, 7, 22, 14, _id),
      trigger: trigger,
      contentHash: 'hash-$text',
      characterCount: text.length,
      isProtected: isManual,
      label: isManual ? label : null,
      note: isManual ? note : null,
    );
    list.add((snapshot: snap, text: text));
    return snap;
  }

  @override
  Future<String> readSnapshotText(
    LibraryAccess access, {
    required DocumentIdentity doc,
    required String snapshotId,
  }) async {
    final entries = _store[doc.logicalKey] ?? const [];
    return entries.firstWhere((e) => e.snapshot.id == snapshotId).text;
  }

  @override
  Future<void> deleteSnapshot(
    LibraryAccess access, {
    required DocumentIdentity doc,
    required String snapshotId,
  }) async {
    final list = _store[doc.logicalKey];
    if (list == null) return;
    list.removeWhere((e) => e.snapshot.id == snapshotId);
  }

  @override
  Future<void> prune(LibraryAccess access, DocumentIdentity doc) async {}
}

final class _FakeDocuments implements DocumentRepository {
  final Map<String, _FakeDoc> _docs = {};
  bool forceConflict = false;

  void seed(String path, String text, {required String revision}) {
    _docs[path] = _FakeDoc(text: text, revision: revision);
  }

  String textOf(String path) => _docs[path]!.text;

  @override
  Future<DocumentSnapshot> readDocument(
    LibraryAccess access,
    DocumentRef ref,
  ) async {
    final d = _docs[ref.relativePath];
    if (d == null) {
      throw StateError('document not seeded: ${ref.relativePath}');
    }
    return DocumentSnapshot(
      ref: ref,
      text: d.text,
      encoding: TextEncoding.utf8,
      lineEnding: LineEnding.lf,
      revision: DocumentRevision(d.revision),
    );
  }

  @override
  Future<DocumentSaveResult> saveDocument(
    LibraryAccess access, {
    required DocumentSnapshot original,
    required String text,
  }) async {
    if (forceConflict) {
      return DocumentSaveConflict(await readDocument(access, original.ref));
    }
    final d = _docs[original.ref.relativePath]!;
    final next = 'r${int.parse(d.revision.substring(1)) + 1}';
    d.text = text;
    d.revision = next;
    return DocumentSaveSuccess(
      DocumentSnapshot(
        ref: original.ref,
        text: text,
        encoding: original.encoding,
        lineEnding: original.lineEnding,
        revision: DocumentRevision(next),
      ),
    );
  }

  @override
  Stream<DocumentChange> watchDocuments(LibraryAccess access) async* {}
}

final class _FakeDoc {
  _FakeDoc({required this.text, required this.revision});
  String text;
  String revision;
}
