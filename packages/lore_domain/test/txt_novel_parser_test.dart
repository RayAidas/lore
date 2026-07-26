import 'package:lore_domain/lore_domain.dart';
import 'package:test/test.dart';

/// 把区段按文档顺序展平为章节列表（断言章节顺序/副标题/正文时用）。
List<NovelChapterImport> _flat(ParsedTxtNovel parsed) => [
  for (final section in parsed.sections)
    ...switch (section) {
      ParsedRootChapters(:final chapters) => chapters,
      ParsedVolume(:final chapters) => chapters,
    },
];

void main() {
  group('TxtNovelParser', () {
    test('splits arabic-numbered chapters and drops leading matter', () {
      final parsed = TxtNovelParser.parse(
        text:
            '作者：佚名\n网址：x\n\n'
            '第1章 起点\n起点正文。\n第二段。\n\n'
            '第2章 远行\n远行正文。',
        fileName: '我的小说.txt',
      );
      expect(parsed.titleSuggestion, '我的小说');
      expect(_flat(parsed), hasLength(2));
      expect(_flat(parsed)[0].subtitle, '起点');
      expect(_flat(parsed)[0].body, '　　起点正文。\n　　第二段。');
      expect(_flat(parsed)[1].subtitle, '远行');
      expect(_flat(parsed)[1].body, '　　远行正文。');
    });

    test('recognizes chinese-numbered headings', () {
      final parsed = TxtNovelParser.parse(text: '第一章 龙城\n正文A\n第二章 飞将\n正文B');
      expect(_flat(parsed), hasLength(2));
      expect(_flat(parsed)[0].subtitle, '龙城');
      expect(_flat(parsed)[1].subtitle, '飞将');
    });

    test('recognizes 第N回/第N节 and Chapter N', () {
      final parsed = TxtNovelParser.parse(
        text: '第一回 桃园\nA\nChapter 2 Begins\nB',
      );
      expect(_flat(parsed), hasLength(2));
      expect(_flat(parsed)[0].subtitle, '桃园');
      expect(_flat(parsed)[1].subtitle, 'Begins');
    });

    test('recognizes role keywords as chapter boundaries', () {
      final parsed = TxtNovelParser.parse(
        text: '序章 楔子\n序言正文\n第1章 正篇\n正文\n后记 结语\n后记正文',
      );
      expect(_flat(parsed), hasLength(3));
      expect(_flat(parsed)[0].subtitle, '楔子');
      expect(_flat(parsed)[2].subtitle, '结语');
    });

    test('groups combined volume+chapter headings into a volume', () {
      final parsed = TxtNovelParser.parse(
        text:
            '第二十六章 风雨欲来\n风雨正文\n'
            '第六卷 破茧成蝶 第一章 水府四殿\n水府正文\n'
            '第六卷 破茧成蝶 第二章 珍宝\n珍宝正文',
      );
      expect(parsed.sections, hasLength(2));
      // 第一段：根章节（卷出现之前）。
      final root = parsed.sections[0] as ParsedRootChapters;
      expect(root.chapters.single.subtitle, '风雨欲来');
      // 第二段：卷《破茧成蝶》含两章。
      final vol = parsed.sections[1] as ParsedVolume;
      expect(vol.name, '破茧成蝶');
      expect(vol.chapters, hasLength(2));
      expect(vol.chapters[0].subtitle, '水府四殿');
      expect(vol.chapters[0].body, '　　水府正文');
      expect(vol.chapters[1].subtitle, '珍宝');
    });

    test('keeps plain chapters inside the current volume', () {
      // 卷一旦确立，后续无卷前缀的章节归入该卷，直到出现新卷名。
      final parsed = TxtNovelParser.parse(
        text:
            '第六卷 破茧成蝶 第一章 水府四殿\n水府正文\n'
            '第二十章 赤明九天\n赤明正文',
      );
      final vol = parsed.sections.single as ParsedVolume;
      expect(vol.name, '破茧成蝶');
      expect(vol.chapters, hasLength(2));
      expect(vol.chapters[1].subtitle, '赤明九天');
    });

    test('splits combined heading without space before chapter token', () {
      final parsed = TxtNovelParser.parse(text: '第六卷 破茧成蝶第十七章 纪宁战童玉\n正文');
      expect(_flat(parsed), hasLength(1));
      expect(_flat(parsed).single.subtitle, '纪宁战童玉');
    });

    test('recognizes full-width digits in headings', () {
      final parsed = TxtNovelParser.parse(text: '第１章 龙城\nA\n第２章 飞将\nB');
      expect(_flat(parsed), hasLength(2));
      expect(_flat(parsed)[0].subtitle, '龙城');
      expect(_flat(parsed)[1].subtitle, '飞将');
    });

    test('tolerates internal spaces around the number', () {
      final parsed = TxtNovelParser.parse(text: '第 1 章 龙城\nA\n第 2 章 飞将\nB');
      expect(_flat(parsed), hasLength(2));
      expect(_flat(parsed)[0].subtitle, '龙城');
      expect(_flat(parsed)[1].subtitle, '飞将');
    });

    test(
      'strips leading bracket decoration and closing bracket from subtitle',
      () {
        final parsed = TxtNovelParser.parse(text: '【第1章】龙城\nA\n《第二章》飞将\nB');
        expect(_flat(parsed), hasLength(2));
        expect(_flat(parsed)[0].subtitle, '龙城');
        expect(_flat(parsed)[1].subtitle, '飞将');
      },
    );

    test('opens a volume on a clean standalone volume header', () {
      // 干净独立卷头（短行、卷名无标点）开卷；其后的纯章节归该卷。
      final parsed = TxtNovelParser.parse(
        text: '第一卷 风起\n第一章 云\n云正文\n第二卷 雨聚\n第二章 雨\n雨正文',
      );
      expect(parsed.sections, hasLength(2));
      final v1 = parsed.sections[0] as ParsedVolume;
      expect(v1.name, '风起');
      expect(v1.chapters.single.subtitle, '云');
      final v2 = parsed.sections[1] as ParsedVolume;
      expect(v2.name, '雨聚');
      expect(v2.chapters.single.subtitle, '雨');
    });

    test('treats prose mentioning 第N卷 as body, not a volume header', () {
      // 「第八卷'应龙卫'开始！」这类作者碎碎念不是卷头，应作为正文。
      final parsed = TxtNovelParser.parse(
        text: '第1章 开端\n开端正文\n第八卷应龙卫开始！\n第2章 继续\n继续正文',
      );
      expect(_flat(parsed), hasLength(2));
      // 仍在同一根区段，卷碎碎念行落入第一章正文。
      expect(_flat(parsed)[0].body, contains('第八卷应龙卫开始！'));
    });

    test('falls back to a single chapter when no heading is found', () {
      final parsed = TxtNovelParser.parse(text: '  整段没有标题的文字。  \n第二行。');
      expect(_flat(parsed), hasLength(1));
      expect(_flat(parsed).single.subtitle, isEmpty);
      expect(_flat(parsed).single.body, '　　整段没有标题的文字。\n　　第二行。');
    });

    test('skips headings but yields no chapters for whitespace-only text', () {
      final parsed = TxtNovelParser.parse(text: '   \n  \n');
      expect(_flat(parsed), isEmpty);
    });

    test('tolerates leading whitespace before headings', () {
      final parsed = TxtNovelParser.parse(
        text: '   第1章 缩进标题\n正文\n\t第2章 制表符\n正文2',
      );
      expect(_flat(parsed), hasLength(2));
      expect(_flat(parsed)[0].subtitle, '缩进标题');
      expect(_flat(parsed)[1].subtitle, '制表符');
    });

    test('strips separators between heading label and subtitle', () {
      final parsed = TxtNovelParser.parse(
        text: '第1章：带冒号的标题\n正文\n第2章 - 带破折号\n正文2',
      );
      expect(_flat(parsed)[0].subtitle, '带冒号的标题');
      expect(_flat(parsed)[1].subtitle, '带破折号');
    });

    test('normalizes CRLF and CR line endings before splitting', () {
      final parsed = TxtNovelParser.parse(text: '第1章 A\r\n正文A\r第2章 B\n正文B');
      expect(_flat(parsed), hasLength(2));
      expect(_flat(parsed)[0].body, '　　正文A');
      expect(_flat(parsed)[1].body, '　　正文B');
    });

    test(
      'preserves first-paragraph full-width indent while trimming noise',
      () {
        // 原文每段都带两字全角缩进：首段缩进须保留（导入后章节首段要有缩进），
        // 标题后的空行与行尾杂散空格仍应被去掉。
        final parsed = TxtNovelParser.parse(
          text: '第1章 起点\n\n　　起点正文。  \n　　第二段。\n\n',
        );
        expect(_flat(parsed)[0].body, '　　起点正文。\n　　第二段。');
      },
    );

    test('normalizes half-width leading spaces to full-width indent', () {
      // 行首缩进统一归一化为两字全角：半角空格、全角空格都变成 `　　`，
      // 各段段首字符一致、视觉对齐（原文常混用半角/全角缩进）。
      final parsed = TxtNovelParser.parse(
        text: '第1章 起点\n    半角四空格首段\n　　全角缩进第二段',
      );
      expect(_flat(parsed)[0].body, '　　半角四空格首段\n　　全角缩进第二段');
    });

    test(
      'normalizes every paragraph to two-char indent regardless of source',
      () {
        // 每个非空正文段都归一化为两字全角缩进：tab、全角空格、半角空格、顶格
        // 一视同仁，避免半角/顶格来源导入后段首参差不齐。
        final parsed = TxtNovelParser.parse(
          text: '第1章 起\n\t制表符段\n　　全角段\n   三半角段\n  两半角段',
        );
        expect(_flat(parsed)[0].body, '　　制表符段\n　　全角段\n　　三半角段\n　　两半角段');
      },
    );

    test('indents flush paragraphs (top-of-column网络小说来源)', () {
      // 回归：抓取的网络小说常每段顶格（行首无任何空白）。除首段会被编辑器
      // 补缩进外，其余段也须在导入时补齐两字缩进，否则只有首段缩进、其余顶格。
      final parsed = TxtNovelParser.parse(
        text: '第1章 师傅\n李火旺举起捣药杆砸在捣药罐里。\n洞内不止他一个人。\n他继续干自己的活。',
      );
      expect(
        _flat(parsed)[0].body,
        '　　李火旺举起捣药杆砸在捣药罐里。\n　　洞内不止他一个人。\n　　他继续干自己的活。',
      );
    });

    test('sanitizes file name into title suggestion', () {
      final parsed = TxtNovelParser.parse(
        text: '第1章\nx',
        fileName: '/a/b/书*名?.txt',
      );
      expect(parsed.titleSuggestion, '书名');
    });

    test('recognizes headings with exotic leading whitespace (U+FEFF)', () {
      // 预过滤的空白集须与正则 \s 一致；前导 BOM 等不应让标题被漏判。
      final parsed = TxtNovelParser.parse(text: '﻿第1章 标题\n正文A\n第2章 续\n正文B');
      expect(_flat(parsed), hasLength(2));
      expect(_flat(parsed)[0].subtitle, '标题');
      expect(_flat(parsed)[1].subtitle, '续');
    });

    test('drops empty volumes (consecutive standalone volume headers)', () {
      // 连续独立卷头：前一个卷无章节应被丢弃，不留孤儿空卷。
      final parsed = TxtNovelParser.parse(text: '第一卷 风起\n第二卷 雨聚\n第一章 雨\n雨正文');
      expect(parsed.sections, hasLength(1));
      final vol = parsed.sections.single as ParsedVolume;
      expect(vol.name, '雨聚');
      expect(vol.chapters, hasLength(1));
    });

    test('does not treat a long body line starting with 第N章 as a heading', () {
      // 超长行（正文段落）即使以「第1章」开头也不应被误判为标题。
      final parsed = TxtNovelParser.parse(
        text:
            '第1章 开端\n开端正文\n'
            '第1章的秘密就藏在这段非常长的正文叙述里，主角一路前行遇到了许多事情，'
            '翻山越岭跋山涉水经历了无数艰难险阻，遇见了形形色色的人物与妖兽，'
            '这段叙述远超任何正常章节标题的长度，理应作为正文保留在第一章之中而不被切分。\n'
            '第2章 结束\n结束正文',
      );
      expect(_flat(parsed), hasLength(2));
      expect(_flat(parsed)[0].subtitle, '开端');
      expect(_flat(parsed)[0].body, contains('第1章的秘密'));
      expect(_flat(parsed)[1].subtitle, '结束');
    });
  });
}
