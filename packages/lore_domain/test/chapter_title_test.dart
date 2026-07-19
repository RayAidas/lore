import 'package:test/test.dart';
import 'package:lore_domain/lore_domain.dart';

void main() {
  group('ChapterTitleText.titleLine', () {
    test('仅编号当副标题为空', () {
      expect(ChapterTitleText.titleLine(3, ''), '第3章');
      expect(ChapterTitleText.titleLine(3, '   '), '第3章');
    });

    test('编号 + 单空格 + 副标题', () {
      expect(ChapterTitleText.titleLine(3, '甜蜜的家'), '第3章 甜蜜的家');
    });

    test('trim 副标题首尾空白', () {
      expect(ChapterTitleText.titleLine(1, '  开端  '), '第1章 开端');
    });
  });

  group('ChapterTitleText.tryParse', () {
    test('解析「第N章」无副标题', () {
      final parsed = ChapterTitleText.tryParse('第3章\n正文');
      expect(parsed, isNotNull);
      expect(parsed!.number, 3);
      expect(parsed.subtitle, '');
    });

    test('解析「第N章 副标题」', () {
      final parsed = ChapterTitleText.tryParse('第12章 甜蜜的家\n正文第一段');
      expect(parsed, isNotNull);
      expect(parsed!.number, 12);
      expect(parsed.subtitle, '甜蜜的家');
    });

    test('首行无换行也视为标题（仅标题、空正文）', () {
      final parsed = ChapterTitleText.tryParse('第3章');
      expect(parsed, isNotNull);
      expect(parsed!.number, 3);
      expect(parsed.subtitle, '');
    });

    test('保留副标题内部空格', () {
      final parsed = ChapterTitleText.tryParse('第3章 a b c\n');
      expect(parsed!.subtitle, 'a b c');
    });

    test('非章节首行返回 null', () {
      expect(ChapterTitleText.tryParse('第一版\n'), isNull);
      expect(ChapterTitleText.tryParse('序章 引子\n'), isNull);
      expect(ChapterTitleText.tryParse(''), isNull);
      expect(ChapterTitleText.tryParse('随便一段正文'), isNull);
    });
  });

  group('ChapterTitleText.bodyOf', () {
    test('取首个换行之后', () {
      expect(ChapterTitleText.bodyOf('第3章\n第一段\n第二段'), '第一段\n第二段');
    });

    test('无换行为空正文', () {
      expect(ChapterTitleText.bodyOf('第3章'), '');
    });

    test('正文里再次出现「第N章」不重新解析（仅按首个换行切分）', () {
      // 形如目录行混入正文：只有首行被当标题，正文原样保留。
      const full = '第3章\n第4章 简介\n后续正文';
      expect(ChapterTitleText.bodyOf(full), '第4章 简介\n后续正文');
      expect(ChapterTitleText.tryParse(full)!.number, 3);
      expect(ChapterTitleText.tryParse(full)!.subtitle, '');
    });
  });

  group('ChapterTitleText.sanitizeForFilename', () {
    test('保留普通文字与内部空格', () {
      expect(ChapterTitleText.sanitizeForFilename('甜蜜的家'), '甜蜜的家');
      expect(ChapterTitleText.sanitizeForFilename('a b c'), 'a b c');
    });

    test('去掉路径分隔符与各平台非法符号', () {
      expect(
        ChapterTitleText.sanitizeForFilename('a/b\\c:d*e?f"g<h>i|j'),
        'abcdefghij',
      );
    });

    test('去掉 ASCII 控制字符（含换行）', () {
      expect(ChapterTitleText.sanitizeForFilename('a\nb\tc'), 'abc');
    });

    test('剥掉前导点与首尾空白', () {
      expect(ChapterTitleText.sanitizeForFilename('.hidden'), 'hidden');
      expect(ChapterTitleText.sanitizeForFilename('  x  '), 'x');
    });

    test('全非法字符时结果为空', () {
      expect(ChapterTitleText.sanitizeForFilename('///...'), '');
    });
  });

  group('ChapterTitleText.compose', () {
    test('标题 + 换行 + 正文', () {
      expect(ChapterTitleText.compose(3, '甜蜜的家', '第一段'), '第3章 甜蜜的家\n第一段');
    });

    test('空正文仍保留标题后换行', () {
      expect(ChapterTitleText.compose(3, '', ''), '第3章\n');
    });

    test('与 tryParse 往返一致（含副标题）', () {
      const full = '第7章 终章\n尾声\n';
      final parsed = ChapterTitleText.tryParse(full)!;
      final body = ChapterTitleText.bodyOf(full);
      expect(
        ChapterTitleText.compose(parsed.number, parsed.subtitle, body),
        full,
      );
    });
  });

  group('ChapterTitleText Markdown 标题', () {
    test('tryParse 识别带 `# ` 前缀的 H1 标题', () {
      final parsed = ChapterTitleText.tryParse('# 第3章 甜蜜的家\n正文');
      expect(parsed, isNotNull);
      expect(parsed!.number, 3);
      expect(parsed.subtitle, '甜蜜的家');

      final noSubtitle = ChapterTitleText.tryParse('# 第3章\n正文');
      expect(noSubtitle!.number, 3);
      expect(noSubtitle.subtitle, '');
    });

    test('`#` 与数字之间允许零或多个空格', () {
      expect(ChapterTitleText.tryParse('#第3章 X\n')!.subtitle, 'X');
      expect(ChapterTitleText.tryParse('#  第3章 X\n')!.subtitle, 'X');
    });

    test('compose 以 markdown:true 写出 H1 首行', () {
      expect(
        ChapterTitleText.compose(3, '甜蜜的家', '正文', markdown: true),
        '# 第3章 甜蜜的家\n正文',
      );
      expect(ChapterTitleText.compose(3, '', '', markdown: true), '# 第3章\n');
    });

    test('TXT 与 MD 往返各自一致', () {
      const mdFull = '# 第5章 终章\n尾声段';
      final parsed = ChapterTitleText.tryParse(mdFull)!;
      expect(
        ChapterTitleText.compose(
          parsed.number,
          parsed.subtitle,
          ChapterTitleText.bodyOf(mdFull),
          markdown: true,
        ),
        mdFull,
      );
    });
  });
}
