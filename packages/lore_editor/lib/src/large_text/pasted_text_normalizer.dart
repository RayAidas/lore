/// 把从外部粘贴进来的文本换行归一化，使其与本编辑器「一行一段」的
/// 内部模型对齐。
///
/// 主流小说/写作类应用用 `\n\n`（段间空行）分隔段落，而本编辑器用单个
/// `\n` 分段。若原样粘贴，外部那段间的空行会被渲染成一个空白段落，
/// 视觉上就是「多余空行」。这里把连续换行折叠成单个 `\n`，同时把
/// CRLF 与孤立 CR 一并归一化为 LF，消除来源差异。
///
/// 单个 `\n`（段内强制换行，如诗歌、地址）原样保留——只折叠「两个及
/// 以上」的连续换行，避免破坏用户有意的断行。
String normalizePastedText(String text) {
  return text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'\n{2,}'), '\n');
}

/// 给粘贴文本补段首缩进，语义与编辑器内回车开新段对齐：对文本内部的
/// 每个 `\n`，其后未紧跟 [indent] 就补一份，让外部「无缩进」的段落进
/// 来后自动带上两字缩进。
///
/// 是否给文本开头（第一段）补缩进由 [indentAtStart] 决定：插入点在段首
/// （文档开头，或前一个字符是 `\n`）时应传 `true`，让粘贴进来的第一段
/// 也视为新段补缩进；插入点在段中时应传 `false`，第一段作为接续不补。
/// 这区分了「粘贴到段首」与「粘贴到段中」两种场景。
///
/// 必须在 [normalizePastedText] 之后调用：否则缩进会被插进 `\n\n` 之间，
/// 使空行折叠失效。`indent` 为空或文本为空时原样返回。
String indentPastedParagraphs(
  String text,
  String indent, {
  bool indentAtStart = false,
}) {
  if (indent.isEmpty || text.isEmpty) {
    return text;
  }
  // 收集所有需要插入缩进的位置（在该索引之前插入 indent）。
  final insertions = <int>[];
  if (indentAtStart && !text.startsWith(indent)) {
    insertions.add(0);
  }
  for (var i = 0; i < text.length; i += 1) {
    if (text[i] == '\n' && !text.startsWith(indent, i + 1)) {
      insertions.add(i + 1);
    }
  }
  if (insertions.isEmpty) {
    return text;
  }
  final buf = StringBuffer();
  var cursor = 0;
  for (final at in insertions) {
    buf.write(text.substring(cursor, at));
    buf.write(indent);
    cursor = at;
  }
  buf.write(text.substring(cursor));
  return buf.toString();
}

/// 判断 [offset] 在 [document] 中是否落在段首——文档开头，或前一个字符
/// 是 `\n`。用于决定粘贴内容的第一段是否按新段补段首缩进。
///
/// 越界兜底：`offset <= 0` 视为段首；`offset` 超过文档长度则 clamp 到
/// 文末判定。这样即便上层传入无效选区（如 [TextSelection] 的 -1）也
/// 不会越界访问。
///
/// 语义说明：决策只看「替换后插入点」的段首性。当选区跨段（起点落在
/// 某段中间）时，插入点取选区起点，第一段按「接续」处理、不补缩进——
/// 这与替换后该位置的实际段落归属一致。
bool pasteInsertsAtParagraphStart(String document, int offset) {
  if (offset <= 0) {
    return true;
  }
  final clamped = offset > document.length ? document.length : offset;
  return clamped == 0 || document[clamped - 1] == '\n';
}
