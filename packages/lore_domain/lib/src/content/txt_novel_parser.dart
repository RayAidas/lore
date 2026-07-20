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

/// [TxtNovelParser.parse] 的结果。
final class ParsedTxtNovel {
  const ParsedTxtNovel({this.titleSuggestion = '', required this.chapters});

  /// 由文件名推导的书名建议（已 [ChapterTitleText.sanitizeForFilename] 净化）；
  /// 无文件名时为空串，由调用方回退到默认书名。
  final String titleSuggestion;

  /// 解析出的章节（按文档顺序）。无任何章节标题时为单章列表。
  final List<NovelChapterImport> chapters;
}

/// 把整本 TXT 拆成章节的纯逻辑工具：按行首章节标题正则切分。
///
/// 行为约定（可预测、无边界 case）：
/// - 所有章节按出现顺序编号（存储层赋 1..N），原文标题文本进
///   [NovelChapterImport.subtitle]。
/// - 首个章节标题之前的内容（书名/作者/广告/目录）**丢弃**。
/// - 检测不到任何章节标题 → 整篇作为单章（subtitle 空）。
/// - 标题行本身不计入正文。
/// - 纯 `第N卷 卷名`（无章节号）的**卷标记不参与切分**，其行作为正文保留；
///   但「卷+章合并行」如 `第六卷 破茧成蝶 第一章 水府四殿` 会按其中的章节
///   token 切分（卷名不进入副标题）。
abstract final class TxtNovelParser {
  const TxtNovelParser._();

  /// 行首章节标题（容错多种网文排版；按优先级匹配其一即视为标题）：
  /// 1. `第N章/第N节/第N回`，N 为阿拉伯（半/全角）或中文数字；允许 `第 1 章`
  ///    这类内部空白。前可带可选装饰与卷前缀：
  ///    - 装饰：`【】`/`［］`/`[]`/`（）`/`〈〉`/`《》`/`「」`/`『』`/`<>` 等前置括号；
  ///    - 卷前缀：`第M卷 [卷名]` 或古典 `卷M [卷名]`（如 `第六卷 破茧成蝶 第一章 …`、
  ///      `卷一 第一章 …`），卷名不计入副标题。
  /// 2. `Chapter N`（大小写不敏感，N 半/全角）。
  /// 3. 序章/楔子/前言/引子/引言/开篇、番外[篇]/外传、终章/结章/尾声/结语/
  ///    后记/终篇。
  ///
  /// 序号字符含半/全角阿拉伯数字与中文数字（全角数字在部分 GBK 来源 TXT 中
  /// 常见）。行内空白用 `\s*`（行已按 `\n` 切分，不含换行，故 `\s` 不会跨行）。
  static final RegExp _headingPattern = RegExp(
    r'^\s*'
    // 可选前置括号/书名号装饰。
    r'[【［\[\(（〈《「『<]*'
    r'(?:'
    // 可选卷前缀（第M卷 或 卷M）+ 卷名，后跟必须的章节 token；
    // [^\n第]*? 不跨行、不吞章节的「第」。
    r'(?:(?:第\s*[一二三四五六七八九十百千两零〇0-9０-９]+\s*卷|卷\s*[一二三四五六七八九十百千两零〇0-9０-９]+)[^\n第]*?)?'
    r'第\s*[一二三四五六七八九十百千两零〇0-9０-９]+\s*[章节回]'
    r'|chapter\s*[0-9０-９]+'
    // 裸角色关键词需后接空白/行尾/标题分隔符，避免「后记正文」这类正文行被误判。
    r'|(?:序章|楔子|前言|引子|引言|开篇|番外篇?|外传|终章|结章|尾声|结语|后记|终篇)(?=\s|$|[:：—–\-])'
    r')',
    caseSensitive: false,
  );

  /// 行尾空白（含全角空格），用于正文行清洗。
  static final RegExp _trailingWhitespace = RegExp(r'[\s　]+$');

  /// 标题 token 之后的分隔符（空白、冒号、破折号、顿号、点、右括号/书名号等），
  /// 用于剥出副标题（如 `【第1章】标题` 去掉残留的 `】`）。
  static final RegExp _leadingSeparators = RegExp(
    r'^[\s:：、．.．·）)）】\]〉》」』>—–\-]+',
  );

  static ParsedTxtNovel parse({required String text, String? fileName}) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    final chapters = <NovelChapterImport>[];

    final headingIndices = <int>[];
    for (var i = 0; i < lines.length; i++) {
      if (_headingPattern.hasMatch(lines[i])) {
        headingIndices.add(i);
      }
    }

    if (headingIndices.isEmpty) {
      final body = _cleanBody(lines);
      if (body.isNotEmpty) {
        chapters.add(NovelChapterImport(subtitle: '', body: body));
      }
    } else {
      for (var j = 0; j < headingIndices.length; j++) {
        final start = headingIndices[j];
        final end = j + 1 < headingIndices.length
            ? headingIndices[j + 1]
            : lines.length;
        final subtitle = _headingLabel(lines[start]);
        final body = _cleanBody(lines.sublist(start + 1, end));
        chapters.add(NovelChapterImport(subtitle: subtitle, body: body));
      }
    }

    return ParsedTxtNovel(
      titleSuggestion: _titleFromFileName(fileName),
      chapters: chapters,
    );
  }

  /// 从标题行抽取副标题：去掉开头的「第N章/Chapter N/序章…」标签与分隔符，
  /// 保留其后的原标题文本；无后续文本则返回空串。
  static String _headingLabel(String headingLine) {
    final rest = headingLine.replaceFirst(_headingPattern, '');
    return rest.replaceFirst(_leadingSeparators, '').trim();
  }

  /// 清洗正文行：逐行去行尾空白后拼接，再整体去首尾空白。保留行首缩进
  /// （诗歌/对白缩进有意义），仅消除行尾杂散空格。
  static String _cleanBody(Iterable<String> rawLines) {
    final joined = rawLines
        .map((line) => line.replaceFirst(_trailingWhitespace, ''))
        .join('\n');
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
