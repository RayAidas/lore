import 'dart:io';

import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_storage/lore_storage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// prune 的集成测试：分层时间窗淘汰 + gzip 文件删除 + 受保护快照豁免。
void main() {
  late Directory root;
  late StorageBackedLibraryRepository repository;
  late LibraryAccess access;
  late _MutableClock clock;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lore-history-prune-');
    access = LibraryAccess(
      token: root.path,
      displayPath: root.path,
      isPending: false,
    );
    clock = _MutableClock(DateTime.utc(2026, 7, 22, 14, 0));
    repository = StorageBackedLibraryRepository(
      storageFactory: LocalDirectoryStorageFactory(),
      idGenerator: _IncrementingIdGenerator(),
      clock: clock,
    );
    await repository.initialize(access);
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  Future<int> snapshotFileCount(String dirName) async {
    final dir = Directory(
      p.join(root.path, '.lore', 'history', dirName, 'snapshots'),
    );
    if (!await dir.exists()) return 0;
    return dir.listSync().whereType<File>().length;
  }

  test('同一小时桶的老快照被淘汰，gzip 文件随之删除', () async {
    const doc = DocumentIdentity(
      nodeId: 'chapter-1',
      relativePath: '正文/第1章.md',
      format: DocumentFormat.markdown,
    );
    // 三条都在 2–3 小时前：11:00/11:30/11:59（clock 推到过去时间 record）。
    clock.now = DateTime.utc(2026, 7, 22, 11, 0);
    await repository.record(
      access,
      doc: doc,
      text: '11点版本',
      trigger: HistoryTrigger.autoCheckpoint,
    );
    clock.now = DateTime.utc(2026, 7, 22, 11, 30);
    await repository.record(
      access,
      doc: doc,
      text: '11点半版本',
      trigger: HistoryTrigger.autoCheckpoint,
    );
    clock.now = DateTime.utc(2026, 7, 22, 11, 59);
    final newest = await repository.record(
      access,
      doc: doc,
      text: '11点59版本',
      trigger: HistoryTrigger.autoCheckpoint,
    );

    expect(await snapshotFileCount('chapter-1'), 3);

    // 回到 now 做 prune。
    clock.now = DateTime.utc(2026, 7, 22, 14, 0);
    await repository.prune(access, doc);

    final list = await repository.list(access, doc);
    expect(list, hasLength(2));
    expect(list.any((s) => s.id == newest.id), isTrue);
    expect(await snapshotFileCount('chapter-1'), 2);
  });

  test('受保护（手动）快照不参与回收', () async {
    const doc = DocumentIdentity(
      nodeId: 'chapter-1',
      relativePath: '正文/第1章.md',
      format: DocumentFormat.markdown,
    );
    final baseNow = DateTime.utc(2026, 7, 22, 14, 0);
    // 三条都在 ~60 天前（month:2 同桶）：一条手动、两条自动。
    clock.now = baseNow.subtract(const Duration(days: 61));
    final manual = await repository.record(
      access,
      doc: doc,
      text: '手动里程碑',
      trigger: HistoryTrigger.manual,
      label: '里程碑',
    );
    clock.now = baseNow.subtract(const Duration(days: 60, hours: 12));
    await repository.record(
      access,
      doc: doc,
      text: '自动旧',
      trigger: HistoryTrigger.autoCheckpoint,
    );
    clock.now = baseNow.subtract(const Duration(days: 60));
    final autoNew = await repository.record(
      access,
      doc: doc,
      text: '自动新',
      trigger: HistoryTrigger.autoCheckpoint,
    );

    clock.now = baseNow;
    await repository.prune(access, doc);

    final ids = (await repository.list(access, doc)).map((s) => s.id).toSet();
    // 自动同月桶留最新（autoNew）；手动豁免保留。
    expect(ids, {manual.id, autoNew.id});
  });

  test('空历史与无淘汰时 prune 安全无副作用', () async {
    const doc = DocumentIdentity(
      nodeId: 'chapter-1',
      relativePath: '正文/第1章.md',
      format: DocumentFormat.markdown,
    );
    // 单条近期快照，prune 不应删除。
    final snap = await repository.record(
      access,
      doc: doc,
      text: '唯一快照',
      trigger: HistoryTrigger.autoCheckpoint,
    );
    await repository.prune(access, doc);
    final list = await repository.list(access, doc);
    expect(list.single.id, snap.id);
  });
}

final class _IncrementingIdGenerator implements IdGenerator {
  var _value = 0;

  @override
  String generate() {
    _value += 1;
    return '00000000-0000-4000-8000-${_value.toString().padLeft(12, '0')}';
  }
}

final class _MutableClock implements Clock {
  _MutableClock(this._value);

  DateTime _value;

  set now(DateTime value) {
    _value = value;
  }

  @override
  DateTime nowUtc() => _value;
}
