import 'chapter_title.dart';

/// 一份待导入的章节（来自 TXT 解析）：副标题 + 正文。
///
/// 编号不在此处决定——存储层写入时按文档顺序统一赋 1..N，避免源文件分卷
/// 重号（如每卷都从「第1章」开始）导致编号冲突。原文标题文本保留在
/// [subtitle]，作为「第N章 <副标题>」的可编辑副标题部分。
final class NovelChapterImport {
  const NovelChapterImport({required this.subtitle, required this.body});

  final String subtitle;
  final String body;
}

/// 解析出的一个区段：要么是挂在正文根部的章节，要么是一卷（含其章节）。
sealed class ParsedSection {
  const ParsedSection();
}

/// 正文根部的章节（无所属卷）。
final class ParsedRootChapters extends ParsedSection {
  const ParsedRootChapters(this.chapters);

  final List<NovelChapterImport> chapters;
}

/// 一卷：[name] 为卷名（如「破茧成蝶」），[chapters] 为该卷内的章节。
final class ParsedVolume extends ParsedSection {
  const ParsedVolume({this.name = '', required this.chapters});

  final String name;

  final List<NovelChapterImport> chapters;
}

/// [TxtNovelParser.parse] 的结果。
final class ParsedTxtNovel {
  const ParsedTxtNovel({this.titleSuggestion = '', required this.sections});

  /// 由文件名推导的书名建议（已 [ChapterTitleText.sanitizeForFilename] 净化）；
  /// 无文件名时为空串，由调用方回退到默认书名。
  final String titleSuggestion;

  /// 解析出的区段（按文档顺序）：根章节区段总是最前（若有），其后为各卷。
  /// 检测不到任何章节标题时为单个根区段含一章。
  final List<ParsedSection> sections;
}

/// 一个待识别的标题候选（解析第一遍收集，第二遍据此切正文）。
class _HeadRecord {
  _HeadRecord(
    this.line, {
    required this.isVolumeOnly,
    this.volume = '',
    required this.subtitle,
  });

  final int line;

  /// 独立卷头（无章节号），仅用于开卷，不产生章节。
  final bool isVolumeOnly;

  /// 所属卷名（合并行带出，或独立卷头）；根章节为空串。
  final String volume;
  final String subtitle;
}

/// 把整本 TXT 拆成卷与章节的纯逻辑工具。
///
/// 行为约定（可预测、无边界 case）：
/// - 章节按出现顺序全局连续编号（存储层赋 1..N）；原文标题文本进
///   [NovelChapterImport.subtitle]。
/// - 卷由「合并行」`第M卷 卷名 第N章 标题` 带出，或由干净的独立卷头
///   `第M卷 卷名`（短行、卷名无标点）开卷；同卷名连续归一卷，卷名变化开新卷。
/// - 首个章节标题之前的内容（书名/作者/广告/目录）**丢弃**。
/// - 检测不到任何章节标题 → 整篇作为单章（根区段，subtitle 空）。
/// - 标题行本身不计入正文。
abstract final class TxtNovelParser {
  const TxtNovelParser._();

  /// 章节标题正则（可选卷前缀，捕获卷名 group 1 + 副标题 group 2）。
  /// 匹配合并行 `第M卷 卷名 第N章 标题` 与纯章节行 `第N章 标题`、`Chapter N`。
  static final RegExp _headRegex = RegExp(
    r'^\s*[【［\[\(（〈《「『<]*'
    r'(?:(?:第\s*[一二三四五六七八九十百千两零〇0-9０-９]+\s*卷|卷\s*[一二三四五六七八九十百千两零〇0-9０-９]+)([^\n第]*))?'
    r'(?:'
    r'第\s*[一二三四五六七八九十百千两零〇0-9０-９]+\s*[章节回]'
    r'|chapter\s*[0-9０-９]+'
    r')'
    r'\s*(.*)$',
    caseSensitive: false,
  );

  /// 独立卷头检测：仅匹配行首的 `第M卷` / `卷M` token（不吞卷名、不锚行尾）。
  /// 卷名是否干净（短、无句末标点）由 [_isCleanVolumeName] 在代码里校验，
  /// 以此排除「第八卷'应龙卫'开始！」这类正文/作者碎碎念——避免在正则里处理
  /// 引号转义。
  static final RegExp _volumeTokenRegex = RegExp(
    r'^\s*(?:第\s*[一二三四五六七八九十百千两零〇0-9０-９]+\s*卷|卷\s*[一二三四五六七八九十百千两零〇0-9０-９]+)',
  );

  /// 卷名里出现这些句末/分隔标点即视为正文碎碎念，而非干净卷头。
  static final RegExp _prosePunct = RegExp(r'[！？。，；：、．.!?]');

  /// 角色关键词（序章/楔子/…），后接空白/行尾/分隔符（避免「后记正文」误判），
  /// group 1 = 关键词后的副标题。
  static final RegExp _roleRegex = RegExp(
    r'^\s*[【［\[\(（〈《「『<]*(?:序章|楔子|前言|引子|引言|开篇|番外篇?|外传|终章|结章|尾声|结语|后记|终篇)(?=\s|$|[:：—–\-])\s*(.*)$',
  );

  /// 副标题前置分隔符（空白、冒号、破折号、顿号、点、右括号/书名号等）。
  static final RegExp _leadingSeparators = RegExp(
    r'^[\s:：、．.．·）)）】\]〉》」』>—–\-]+',
  );

  /// 可能作为标题行首的字符（UTF-16 码元），用于快速预过滤：行首首个非空白字符
  /// 不在此集合则跳过正则（绝大多数正文行首是普通汉字/缩进，直接排除）。
  static const Set<int> _starterChars = <int>{
    0x43, 0x63, // C c (Chapter)
    0x5B, 0x3C, 0x28, // [ < (
    0x3010, 0xFF3B, 0xFF08, 0x3008, 0x300A, 0x300C, 0x300E, // 【 ［ （ 〈 《 「 『
    0x7B2C, // 第
    0x5377, // 卷
    0x5E8F, 0x695C, 0x524D, 0x5F15, 0x5F00, // 序 楔 前 引 开
    0x756A, 0x5916, // 番 外
    0x7EC8, 0x7ED3, 0x5C3E, 0x540E, // 终 结 尾 后
  };

  static ParsedTxtNovel parse({required String text, String? fileName}) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');

    // 第一遍：快速预过滤 + 正则，收集标题候选。
    final heads = <_HeadRecord>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!_couldBeHeading(line)) {
        continue;
      }
      final m = _headRegex.firstMatch(line);
      if (m != null) {
        final volume = (m.group(1) ?? '').trim();
        final subtitle = _stripSeparators((m.group(2) ?? '').trim());
        heads.add(
          _HeadRecord(
            i,
            isVolumeOnly: false,
            volume: volume,
            subtitle: subtitle,
          ),
        );
        continue;
      }
      final mv = _volumeTokenRegex.firstMatch(line);
      if (mv != null) {
        final name = _stripSeparators(line.substring(mv.end).trim());
        if (_isCleanVolumeName(name)) {
          heads.add(
            _HeadRecord(i, isVolumeOnly: true, volume: name, subtitle: ''),
          );
        }
        // 卷名不干净（含句末标点等）→ 视为正文，不记为标题。
        continue;
      }
      final mr = _roleRegex.firstMatch(line);
      if (mr != null) {
        final subtitle = _stripSeparators((mr.group(1) ?? '').trim());
        heads.add(
          _HeadRecord(i, isVolumeOnly: false, volume: '', subtitle: subtitle),
        );
        continue;
      }
    }

    if (heads.isEmpty) {
      final body = _cleanBody(lines);
      final sections = <ParsedSection>[
        if (body.isNotEmpty)
          ParsedRootChapters([NovelChapterImport(subtitle: '', body: body)]),
      ];
      return ParsedTxtNovel(
        titleSuggestion: _titleFromFileName(fileName),
        sections: sections,
      );
    }

    // 第二遍：按标题切正文，归入卷/根区段。
    final sections = <ParsedSection>[];
    final rootChapters = <NovelChapterImport>[];
    ParsedVolume? currentVolume;

    void openVolume(String name) {
      if (currentVolume == null || currentVolume!.name != name) {
        currentVolume = ParsedVolume(name: name, chapters: []);
        sections.add(currentVolume!);
      }
    }

    for (var h = 0; h < heads.length; h++) {
      final head = heads[h];
      final end = h + 1 < heads.length ? heads[h + 1].line : lines.length;
      final body = _cleanBody(lines.sublist(head.line + 1, end));

      if (head.isVolumeOnly) {
        openVolume(head.volume);
        continue;
      }

      final chapter = NovelChapterImport(subtitle: head.subtitle, body: body);
      if (head.volume.isNotEmpty) {
        openVolume(head.volume);
        currentVolume!.chapters.add(chapter);
      } else if (currentVolume != null) {
        // 无卷前缀的章节：若当前处于某卷中则归该卷。
        currentVolume!.chapters.add(chapter);
      } else {
        rootChapters.add(chapter);
      }
    }

    // 根章节总在最前（卷出现之前的散章）。
    if (rootChapters.isNotEmpty) {
      sections.insert(0, ParsedRootChapters(rootChapters));
    }
    // 丢弃无章节的空卷（连续独立卷头会产生），避免落盘孤儿空卷目录。
    sections.removeWhere((s) => s is ParsedVolume && s.chapters.isEmpty);

    return ParsedTxtNovel(
      titleSuggestion: _titleFromFileName(fileName),
      sections: sections,
    );
  }

  /// 行首首个非空白字符是否可能为标题起始（不分配新字符串，O(行首)）。
  ///
  /// 同时拒绝超长行（标题不会很长，长行是正文段落，借此降低「正文行首提及
  /// 第N章」被误判为标题的概率）。空白判定须与正则 `\s` 一致（否则像
  /// `﻿`/` ` 这类前导字符会让预过滤误删正则本可匹配的标题行）。
  static bool _couldBeHeading(String line) {
    if (line.length > 80) {
      return false;
    }
    for (var i = 0; i < line.length; i++) {
      final c = line.codeUnitAt(i);
      if (_isWhitespace(c)) {
        continue;
      }
      return _starterChars.contains(c);
    }
    return false;
  }

  /// 与 ECMAScript/Dart `\s` 等价的空白码元判定（预过滤必须比正则宽松，
  /// 否则会漏判带特殊前导空白的标题行）。
  static bool _isWhitespace(int c) {
    return c == 0x09 ||
        c == 0x0A ||
        c == 0x0B ||
        c == 0x0C ||
        c == 0x0D ||
        c == 0x20 ||
        c == 0xA0 ||
        c == 0x1680 ||
        c == 0x2028 ||
        c == 0x2029 ||
        c == 0x202F ||
        c == 0x205F ||
        c == 0x3000 ||
        c == 0xFEFF ||
        (c >= 0x2000 && c <= 0x200A);
  }

  static String _stripSeparators(String value) {
    return value.replaceFirst(_leadingSeparators, '').trim();
  }

  /// 独立卷头的卷名是否干净：长度 ≤ 16 且不含句末/分隔标点。
  static bool _isCleanVolumeName(String name) {
    if (name.length > 16) {
      return false;
    }
    return !_prosePunct.hasMatch(name);
  }

  /// 清洗正文行：逐行 `trimRight` 后拼接，再整体去首尾空白。保留行首缩进
  /// （诗歌/对白缩进有意义），仅消除行尾杂散空格。纯字符串操作、无正则。
  static String _cleanBody(Iterable<String> rawLines) {
    final joined = rawLines.map((line) => line.trimRight()).join('\n');
    return joined.trim();
  }

  /// 取文件名 stem（去目录、去扩展名）并净化为安全书名片段。
  static String _titleFromFileName(String? fileName) {
    if (fileName == null || fileName.isEmpty) {
      return '';
    }
    var stem = fileName;
    final slash = stem.lastIndexOf(RegExp(r'[/\\]'));
    if (slash >= 0) {
      stem = stem.substring(slash + 1);
    }
    final dot = stem.lastIndexOf('.');
    if (dot > 0) {
      stem = stem.substring(0, dot);
    }
    return ChapterTitleText.sanitizeForFilename(stem);
  }
}
