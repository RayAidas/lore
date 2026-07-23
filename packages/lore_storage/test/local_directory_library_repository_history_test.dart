import 'dart:io';

import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_storage/lore_storage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late StorageBackedLibraryRepository repository;
  late LibraryAccess access;
  late _MutableClock clock;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lore-history-test-');
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

  DocumentIdentity chapter({
    String nodeId = 'chapter-1',
    String relativePath = '正文/第1章.md',
  }) => DocumentIdentity(
    nodeId: nodeId,
    relativePath: relativePath,
    format: DocumentFormat.markdown,
  );

  test('record 后可列出，readSnapshotText 内容往返一致', () async {
    const doc = DocumentIdentity(
      nodeId: 'chapter-1',
      relativePath: '正文/第1章.md',
      format: DocumentFormat.markdown,
    );
    final snap = await repository.record(
      access,
      doc: doc,
      text: '雨夜倾盆而下。',
      trigger: HistoryTrigger.autoCheckpoint,
    );
    final list = await repository.list(access, doc);
    expect(list, hasLength(1));
    expect(list.single.id, snap.id);
    expect(list.single.trigger, HistoryTrigger.autoCheckpoint);
    expect(list.single.characterCount, characterCountOf('雨夜倾盆而下。'));
    expect(
      await repository.readSnapshotText(access, doc: doc, snapshotId: snap.id),
      '雨夜倾盆而下。',
    );
  });

  test('内容与最新一条相同时去重，不新增快照', () async {
    const doc = DocumentIdentity(
      nodeId: 'chapter-1',
      relativePath: '正文/第1章.md',
      format: DocumentFormat.markdown,
    );
    final first = await repository.record(
      access,
      doc: doc,
      text: '相同内容',
      trigger: HistoryTrigger.autoCheckpoint,
    );
    clock.now = DateTime.utc(2026, 7, 22, 15, 0);
    final second = await repository.record(
      access,
      doc: doc,
      text: '相同内容',
      trigger: HistoryTrigger.autoCheckpoint,
    );
    expect(second.id, first.id, reason: '去重应返回最近一条');
    expect(await repository.list(access, doc), hasLength(1));
  });

  test('内容变化时新增快照，按写入顺序列出', () async {
    const doc = DocumentIdentity(
      nodeId: 'chapter-1',
      relativePath: '正文/第1章.md',
      format: DocumentFormat.markdown,
    );
    final a = await repository.record(
      access,
      doc: doc,
      text: '版本一',
      trigger: HistoryTrigger.autoCheckpoint,
    );
    clock.now = DateTime.utc(2026, 7, 22, 15, 0);
    final b = await repository.record(
      access,
      doc: doc,
      text: '版本二',
      trigger: HistoryTrigger.autoThreshold,
    );
    final list = await repository.list(access, doc);
    expect(list.map((s) => s.id), [a.id, b.id]);
    expect(list.last.trigger, HistoryTrigger.autoThreshold);
  });

  test('改回旧内容仍会新增（去重只比最新一条，不比全部）', () async {
    const doc = DocumentIdentity(
      nodeId: 'chapter-1',
      relativePath: '正文/第1章.md',
      format: DocumentFormat.markdown,
    );
    await repository.record(
      access,
      doc: doc,
      text: 'A',
      trigger: HistoryTrigger.autoCheckpoint,
    );
    clock.now = DateTime.utc(2026, 7, 22, 15, 0);
    await repository.record(
      access,
      doc: doc,
      text: 'B',
      trigger: HistoryTrigger.autoCheckpoint,
    );
    clock.now = DateTime.utc(2026, 7, 22, 16, 0);
    await repository.record(
      access,
      doc: doc,
      text: 'A',
      trigger: HistoryTrigger.autoCheckpoint,
    );
    expect(await repository.list(access, doc), hasLength(3));
  });

  test('手动快照带命名备注且受保护，自动快照不带', () async {
    const doc = DocumentIdentity(
      nodeId: 'chapter-1',
      relativePath: '正文/第1章.md',
      format: DocumentFormat.markdown,
    );
    final manual = await repository.record(
      access,
      doc: doc,
      text: '交稿版',
      trigger: HistoryTrigger.manual,
      label: '交稿前',
      note: '改完伏笔',
    );
    expect(manual.isProtected, isTrue);
    expect(manual.label, '交稿前');
    expect(manual.note, '改完伏笔');

    clock.now = DateTime.utc(2026, 7, 22, 15, 0);
    final auto = await repository.record(
      access,
      doc: doc,
      text: '继续写',
      trigger: HistoryTrigger.autoCheckpoint,
      // 自动触发即使误传 label 也应被忽略。
      label: '不应出现',
    );
    expect(auto.isProtected, isFalse);
    expect(auto.label, isNull);
    expect(auto.note, isNull);
  });

  test('不同章节身份隔离，互不干扰', () async {
    final docA = chapter(nodeId: 'chapter-a', relativePath: '正文/第1章.md');
    final docB = chapter(nodeId: 'chapter-b', relativePath: '正文/第2章.md');
    await repository.record(
      access,
      doc: docA,
      text: 'A 内容',
      trigger: HistoryTrigger.autoCheckpoint,
    );
    expect(await repository.list(access, docA), hasLength(1));
    expect(await repository.list(access, docB), isEmpty);
  });

  test('普通文件无 nodeId 退化路径关联，与章节文档隔离', () async {
    const fileDoc = DocumentIdentity(
      relativePath: '长夜行/大纲.md',
      format: DocumentFormat.markdown,
    );
    final snap = await repository.record(
      access,
      doc: fileDoc,
      text: '大纲内容',
      trigger: HistoryTrigger.autoCheckpoint,
    );
    expect(await repository.list(access, fileDoc), hasLength(1));
    expect(
      await repository.readSnapshotText(
        access,
        doc: fileDoc,
        snapshotId: snap.id,
      ),
      '大纲内容',
    );
    // 同 relativePath 但作为章节（有 nodeId）应隔离。
    const chapterDoc = DocumentIdentity(
      nodeId: 'outline-node',
      relativePath: '长夜行/大纲.md',
      format: DocumentFormat.markdown,
    );
    expect(await repository.list(access, chapterDoc), isEmpty);
  });

  test('deleteSnapshot 移除条目，再读取抛 notFound', () async {
    const doc = DocumentIdentity(
      nodeId: 'chapter-1',
      relativePath: '正文/第1章.md',
      format: DocumentFormat.markdown,
    );
    final snap = await repository.record(
      access,
      doc: doc,
      text: '待删除',
      trigger: HistoryTrigger.autoCheckpoint,
    );
    await repository.deleteSnapshot(access, doc: doc, snapshotId: snap.id);
    expect(await repository.list(access, doc), isEmpty);
    expect(
      () => repository.readSnapshotText(access, doc: doc, snapshotId: snap.id),
      throwsA(isA<LibraryOperationException>()),
    );
  });

  test('快照文件以 gzip 存储（.txt.gz 后缀）', () async {
    const doc = DocumentIdentity(
      nodeId: 'chapter-1',
      relativePath: '正文/第1章.md',
      format: DocumentFormat.markdown,
    );
    await repository.record(
      access,
      doc: doc,
      text: '压缩检查',
      trigger: HistoryTrigger.autoCheckpoint,
    );
    final snapshotsDir = Directory(
      p.join(root.path, '.lore', 'history', 'chapter-1', 'snapshots'),
    );
    final files = snapshotsDir.listSync();
    expect(files, hasLength(1));
    expect(p.extension(files.single.path), '.gz');
  });

  test('快照文件丢失或损坏时 readSnapshotText 抛 notFound', () async {
    const doc = DocumentIdentity(
      nodeId: 'chapter-1',
      relativePath: '正文/第1章.md',
      format: DocumentFormat.markdown,
    );
    final snap = await repository.record(
      access,
      doc: doc,
      text: '即将丢失',
      trigger: HistoryTrigger.autoCheckpoint,
    );
    // manifest 已记录，但 gzip 文件被外部删除。
    final snapshotsDir = Directory(
      p.join(root.path, '.lore', 'history', 'chapter-1', 'snapshots'),
    );
    for (final file in snapshotsDir.listSync().whereType<File>()) {
      file.deleteSync();
    }
    expect(
      () => repository.readSnapshotText(access, doc: doc, snapshotId: snap.id),
      throwsA(isA<LibraryOperationException>()),
    );
    // list 仍返回该条（manifest 是权威，文件丢失不影响元信息列举）。
    final list = await repository.list(access, doc);
    expect(list.any((s) => s.id == snap.id), isTrue);
  });

  test('不同快照文件名互不碰撞', () async {
    const doc = DocumentIdentity(
      nodeId: 'chapter-1',
      relativePath: '正文/第1章.md',
      format: DocumentFormat.markdown,
    );
    await repository.record(
      access,
      doc: doc,
      text: '版本一',
      trigger: HistoryTrigger.autoCheckpoint,
    );
    clock.now = DateTime.utc(2026, 7, 22, 15, 0);
    await repository.record(
      access,
      doc: doc,
      text: '版本二',
      trigger: HistoryTrigger.autoCheckpoint,
    );
    final snapshotsDir = Directory(
      p.join(root.path, '.lore', 'history', 'chapter-1', 'snapshots'),
    );
    final names = snapshotsDir
        .listSync()
        .map((entry) => p.basename(entry.path))
        .toSet();
    expect(names.length, 2);
  });

  test('时钟回拨后去重仍按最新一条判定', () async {
    const doc = DocumentIdentity(
      nodeId: 'chapter-1',
      relativePath: '正文/第1章.md',
      format: DocumentFormat.markdown,
    );
    clock.now = DateTime.utc(2026, 7, 22, 14, 0);
    await repository.record(
      access,
      doc: doc,
      text: '内容X',
      trigger: HistoryTrigger.autoCheckpoint,
    );
    // 时钟回拨到更早时刻：latest 仍应是 14:00 那条（createdAt 更大）。
    clock.now = DateTime.utc(2026, 7, 22, 10, 0);
    final second = await repository.record(
      access,
      doc: doc,
      text: '内容X',
      trigger: HistoryTrigger.autoCheckpoint,
    );
    final list = await repository.list(access, doc);
    expect(list, hasLength(1));
    expect(list.single.id, second.id);
  });

  test('manifest 损坏（旧版残留 / 写入中断）时 list 返回空而非抛错', () async {
    const doc = DocumentIdentity(
      nodeId: 'chapter-corrupt',
      relativePath: '正文/损坏.md',
      format: DocumentFormat.markdown,
    );
    // 直接写入无法解析的 manifest，模拟旧版 schema 残留或崩溃中断。
    final manifestPath = p.join(
      root.path,
      '.lore',
      'history',
      'chapter-corrupt',
      'manifest.json',
    );
    await Directory(p.dirname(manifestPath)).create(recursive: true);
    await File(manifestPath).writeAsString('{ 不是合法 json');
    expect(await repository.list(access, doc), isEmpty);
  });

  test('manifest 为空文件（createFile 后写入前崩溃）时 list 返回空而非抛错', () async {
    const doc = DocumentIdentity(
      nodeId: 'chapter-empty',
      relativePath: '正文/空.md',
      format: DocumentFormat.markdown,
    );
    // 0 字节 manifest：模拟 exclusive createFile 成功、writeAsBytes 前进程被杀。
    final manifestPath = p.join(
      root.path,
      '.lore',
      'history',
      'chapter-empty',
      'manifest.json',
    );
    await Directory(p.dirname(manifestPath)).create(recursive: true);
    await File(manifestPath).writeAsBytes(const []);
    expect(await repository.list(access, doc), isEmpty);
  });

  test('manifest 损坏后 record 以 replace 覆盖重建，恢复列举', () async {
    const doc = DocumentIdentity(
      nodeId: 'chapter-corrupt',
      relativePath: '正文/损坏.md',
      format: DocumentFormat.markdown,
    );
    final manifestPath = p.join(
      root.path,
      '.lore',
      'history',
      'chapter-corrupt',
      'manifest.json',
    );
    await Directory(p.dirname(manifestPath)).create(recursive: true);
    await File(manifestPath).writeAsString('{ broken');
    expect(await repository.list(access, doc), isEmpty);

    await repository.record(
      access,
      doc: doc,
      text: '修复后内容',
      trigger: HistoryTrigger.autoCheckpoint,
    );
    final list = await repository.list(access, doc);
    expect(list, hasLength(1));
    expect(list.single.characterCount, characterCountOf('修复后内容'));
  });

  test('0 字节 manifest（用户实测场景）后 record 覆盖重建，恢复列举', () async {
    const doc = DocumentIdentity(
      nodeId: 'chapter-empty-repair',
      relativePath: '正文/空修复.md',
      format: DocumentFormat.markdown,
    );
    final manifestPath = p.join(
      root.path,
      '.lore',
      'history',
      'chapter-empty-repair',
      'manifest.json',
    );
    await Directory(p.dirname(manifestPath)).create(recursive: true);
    await File(manifestPath).writeAsBytes(const []);
    expect(await repository.list(access, doc), isEmpty);

    await repository.record(
      access,
      doc: doc,
      text: '修复后内容',
      trigger: HistoryTrigger.autoCheckpoint,
    );
    final list = await repository.list(access, doc);
    expect(list, hasLength(1));
    expect(list.single.characterCount, characterCountOf('修复后内容'));
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
