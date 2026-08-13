import 'package:lore_application/lore_application.dart';
import 'package:test/test.dart';

void main() {
  group('formatSettingMemoryHeader', () {
    test('wraps a fixed heading with the generation basis and date', () {
      final header = formatSettingMemoryHeader(now: DateTime.utc(2026, 8, 13));
      expect(header, startsWith('# 设定记忆'));
      expect(header, contains('基于章节记忆生成'));
      expect(header, contains('2026-08-13'));
    });
  });

  group('parseSettingMemoryCounts', () {
    test('counts entries under each recognized category', () {
      const text = '''
# 设定记忆
> 基于章节记忆生成 · 2026-08-13

## 人物
### 林晚
- 身份：主角

### 沈辞
- 身份：配角

## 地点
### 临渊城
- 类型：城市

## 时间线
### 第3章 林晚入城
- 章节：第3章

## 伏笔
### 铜铃
- 埋设章节：第7章
''';
      final counts = parseSettingMemoryCounts(text);
      expect(counts.characters, 2);
      expect(counts.locations, 1);
      expect(counts.timeline, 1);
      expect(counts.foreshadowing, 1);
      expect(counts.total, 5);
    });

    test('ignores entries before the first ## category (doc header)', () {
      const text = '''
# 设定记忆
> 基于章节记忆生成 · 2026-08-13

### 杂项
不应计入。

## 人物
### 林晚
- 身份：主角
''';
      final counts = parseSettingMemoryCounts(text);
      expect(counts.characters, 1);
      expect(counts.total, 1);
    });

    test('ignores ### entries under an unrecognized category', () {
      const text = '''
## 人物
### 林晚

### 沈辞

## 附录
### 参考资料
''';
      final counts = parseSettingMemoryCounts(text);
      expect(counts.characters, 2);
      expect(counts.locations, 0);
      expect(counts.timeline, 0);
      expect(counts.foreshadowing, 0);
    });

    test('accepts common category aliases', () {
      const text = '''
## 人物卡
### 林晚

## 大事记
### 事件一

## 场景
### 茶馆
''';
      final counts = parseSettingMemoryCounts(text);
      expect(counts.characters, 1);
      expect(counts.timeline, 1);
      expect(counts.locations, 1);
      expect(counts.total, 3);
    });

    test('empty text counts zero', () {
      final counts = parseSettingMemoryCounts('');
      expect(counts.characters, 0);
      expect(counts.locations, 0);
      expect(counts.timeline, 0);
      expect(counts.foreshadowing, 0);
      expect(counts.total, 0);
    });
  });
}
