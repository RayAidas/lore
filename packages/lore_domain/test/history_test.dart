import 'package:lore_domain/lore_domain.dart';
import 'package:test/test.dart';

void main() {
  group('DocumentIdentity', () {
    test('章节用 nodeId 生成 node: 逻辑键并标记稳定身份', () {
      const id = DocumentIdentity(
        nodeId: 'abc-123',
        relativePath: '正文/第一卷/第1章.md',
        format: DocumentFormat.markdown,
      );
      expect(id.logicalKey, 'node:abc-123');
      expect(id.hasStableId, isTrue);
    });

    test('普通文件无 nodeId 退化为 path: 逻辑键', () {
      const id = DocumentIdentity(
        relativePath: '长夜行/大纲.md',
        format: DocumentFormat.markdown,
      );
      expect(id.logicalKey, 'path:长夜行/大纲.md');
      expect(id.hasStableId, isFalse);
    });

    test('身份相等性基于 nodeId、路径与格式', () {
      const a = DocumentIdentity(
        nodeId: 'abc',
        relativePath: 'p',
        format: DocumentFormat.markdown,
      );
      const b = DocumentIdentity(
        nodeId: 'abc',
        relativePath: 'p',
        format: DocumentFormat.markdown,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('相同路径但 nodeId 有无不同则身份不同', () {
      const withId = DocumentIdentity(
        nodeId: 'abc',
        relativePath: 'p',
        format: DocumentFormat.markdown,
      );
      const withoutId = DocumentIdentity(
        relativePath: 'p',
        format: DocumentFormat.markdown,
      );
      expect(withId, isNot(equals(withoutId)));
    });

    test('格式不同则身份不同', () {
      const md = DocumentIdentity(
        relativePath: 'p',
        format: DocumentFormat.markdown,
      );
      const txt = DocumentIdentity(
        relativePath: 'p',
        format: DocumentFormat.text,
      );
      expect(md, isNot(equals(txt)));
    });
  });

  group('HistorySnapshot', () {
    final createdAt = DateTime.utc(2026, 7, 22, 14, 30);

    test('manual 触发判定为手动且受保护', () {
      final snap = HistorySnapshot(
        id: 's1',
        createdAt: createdAt,
        trigger: HistoryTrigger.manual,
        contentHash: 'h',
        characterCount: 100,
        isProtected: true,
        label: '交稿前',
        note: '改完伏笔',
      );
      expect(snap.isManual, isTrue);
      expect(snap.isProtected, isTrue);
      expect(snap.label, '交稿前');
    });

    test('自动触发判定为非手动', () {
      for (final trigger in [
        HistoryTrigger.autoCheckpoint,
        HistoryTrigger.autoThreshold,
        HistoryTrigger.restoreSafeguard,
      ]) {
        final snap = HistorySnapshot(
          id: 's2',
          createdAt: createdAt,
          trigger: trigger,
          contentHash: 'h',
          characterCount: 100,
          isProtected: false,
        );
        expect(snap.isManual, isFalse, reason: trigger.name);
        expect(snap.label, isNull);
        expect(snap.note, isNull);
      }
    });
  });
}
