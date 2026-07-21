/// 章节标题文本的纯逻辑工具：把「第N章 [副标题]」这一行与文件正文之间互转。
///
/// 章节文件的首行即标题，形如 `第3章` 或 `第3章 甜蜜的家`；其后的内容为正文。
/// 编号 `N` 来自章节序号（由文件名 `^第(\d+)章` 在 reconcile 时回填到
/// [ContentNode.number]），UI 侧据此渲染**只读**锁定前缀 `第N章`，副标题部分
/// 可编辑。本类只做字符串拆分与重组，不涉及任何 Flutter 依赖，便于单测。
abstract final class ChapterTitleText {
  const ChapterTitleText._();

  /// TXT 首行标题：列首 `第N章`（无前导空白、无 `#`）。
  static final _txtPrefixPattern = RegExp(r'^第(\d+)章');

  /// Markdown 首行标题：规范 H1 `# 第N章`（`#` 后至少一个空白）。
  /// 拒绝 `#第N章`（非 CommonMark 标题）与不带 `#` 的纯 `第N章`——后者会令散落
  /// 的 MD 文件被误判为章节、并在保存时被插入 `#`。
  static final _mdPrefixPattern = RegExp(r'^#[ \t]+第(\d+)章');

  /// 文件名非法字符：路径分隔符、各平台保留符号、ASCII 控制字符。
  /// 公开供输入过滤器与 [sanitizeForFilename] 共用，确保「文件首行」与
  /// 「文件名」按同一规则清洗。
  static final RegExp filenameIllegalChars = RegExp(r'[/\\:*?"<>|\x00-\x1F]');

  /// 锁定前缀，例如 `第3章`。
  static String prefix(int number) => '第$number章';

  /// 把副标题净化为可作文件名一部分的安全串：去掉路径分隔符、各平台文件名
  /// 非法符号与控制字符，并剥掉前导点（避免隐藏文件名 / 触发存储层 `_validName`
  /// 拒绝）与首尾空白。结果可能为空（调用方负责回退为 `第N章`）。
  static String sanitizeForFilename(String value) {
    final stripped = value.replaceAll(filenameIllegalChars, '').trim();
    var start = 0;
    while (start < stripped.length && stripped.codeUnitAt(start) == 0x2E) {
      // '.' 0x2E
      start += 1;
    }
    return stripped.substring(start);
  }

  /// 标题整行：副标题为空时仅 `第N章`，否则 `第N章 副标题`（单个空格分隔）。
  static String titleLine(int number, String subtitle) {
    final trimmed = subtitle.trim();
    return trimmed.isEmpty ? prefix(number) : '${prefix(number)} $trimmed';
  }

  /// 由完整文件文本按 [markdown] 对应的规则解析标题；首行不匹配返回 null
  /// （非章节标题）。TXT 用列首 `第N章`；Markdown 用规范 H1 `# 第N章`。
  static ChapterTitleParts? tryParse(String fullText, {bool markdown = false}) {
    final lineBreak = fullText.indexOf('\n');
    final firstLine = lineBreak < 0
        ? fullText
        : fullText.substring(0, lineBreak);
    final match = (markdown ? _mdPrefixPattern : _txtPrefixPattern).firstMatch(
      firstLine,
    );
    if (match == null) {
      return null;
    }
    final number = int.parse(match.group(1)!);
    var subtitle = firstLine.substring(match.end);
    // 剥掉前缀与副标题之间最多一个分隔空白；副标题内部的空白保留。
    if (subtitle.startsWith(' ')) {
      subtitle = subtitle.substring(1);
    }
    return ChapterTitleParts(number: number, subtitle: subtitle);
  }

  /// 首行是否为章节标题（TXT `第N章` 或 Markdown `# 第N章`），不解析编号
  /// 与副标题。比 [tryParse] 轻量（无 `int.parse` 与对象分配），供只需判断
  /// 无需解析的场景（如字数统计）使用。严格规则：TXT 列首无前导空白；
  /// Markdown 的 `#` 后须至少一个空白（拒绝 `#第N章`）。
  static bool hasTitlePrefix(String fullText) {
    final lineBreak = fullText.indexOf('\n');
    final firstLine = lineBreak < 0
        ? fullText
        : fullText.substring(0, lineBreak);
    return _txtPrefixPattern.hasMatch(firstLine) ||
        _mdPrefixPattern.hasMatch(firstLine);
  }

  /// 正文部分：首个换行之后的内容；无换行时为空串。
  static String bodyOf(String fullText) {
    final lineBreak = fullText.indexOf('\n');
    return lineBreak < 0 ? '' : fullText.substring(lineBreak + 1);
  }

  /// 重组完整文件文本：标题行 + 换行 + 正文。正文为空时仍保留标题后的换行，
  /// 使「标题 / 正文」结构稳定，光标自然落在空正文段。
  ///
  /// [markdown] 为真时标题行以 `# ` 前缀写作 Markdown H1（文件首行保持 Markdown
  /// 语义）；文件名与标题栏显示均不含 `#`（仅磁盘首行有）。
  static String compose(
    int number,
    String subtitle,
    String body, {
    bool markdown = false,
  }) {
    final head = markdown
        ? '# ${titleLine(number, subtitle)}'
        : titleLine(number, subtitle);
    return '$head\n$body';
  }
}

/// [ChapterTitleText.tryParse] 的解析结果。
final class ChapterTitleParts {
  const ChapterTitleParts({required this.number, required this.subtitle});

  final int number;
  final String subtitle;
}
