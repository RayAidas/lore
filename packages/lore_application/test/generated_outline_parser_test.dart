import 'package:lore_application/lore_application.dart';
import 'package:test/test.dart';

void main() {
  const parser = GeneratedOutlineParser();

  test('splits step-one output into world and character sections', () {
    const text = '''
# 世界观
灵气复苏的东方世界，王朝与宗门并立。

# 人物设定
林晚：孤僻天才。

## 第一卷
（二级标题属于正文，不应被当作切分边界）
''';

    final result = parser.splitStepOne(text);

    expect(result.world, contains('灵气复苏的东方世界'));
    expect(result.world, isNot(contains('林晚')));
    expect(result.characters, contains('林晚'));
    expect(result.characters, isNot(contains('灵气复苏')));
    // 二级标题内容保留在人物设定节正文里。
    expect(result.characters, contains('第一卷'));
  });

  test('recognizes heading aliases 世界背景 and 角色设定', () {
    final result = parser.splitStepOne('''
# 世界背景
蛮荒大陆。

# 角色设定
主角：沈夜。
''');

    expect(result.world, '蛮荒大陆。');
    expect(result.characters, '主角：沈夜。');
  });

  test('heading with extra text after alias still matches', () {
    final result = parser.splitStepOne('''
# 世界观：洪荒时代
灵气浓郁。

# 人物设定（主要角色）
鸿钧。
''');

    expect(result.world, '灵气浓郁。');
    expect(result.characters, '鸿钧。');
  });

  test('returns null for a missing section', () {
    final result = parser.splitStepOne('''
# 世界观
只有世界观。
''');

    expect(result.world, '只有世界观。');
    expect(result.characters, isNull);
  });

  test('falls back to whole text when no heading is found', () {
    const text = '没有任何标题的正文。';
    final result = parser.splitStepOne(text);

    expect(result.world, text);
    expect(result.characters, isNull);
  });

  test('returns empty sections for empty input', () {
    final result = parser.splitStepOne('');

    expect(result.world, isNull);
    expect(result.characters, isNull);
  });
}
