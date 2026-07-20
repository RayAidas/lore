import 'chapter_title.dart';

/// 章节正文字数（不含标题行）：先归一化行尾，再当首行是章节标题（TXT
/// `第N章` 或 Markdown `# 第N章`）时剥离标题行，最后对剩余正文去所有空白
/// 按 Unicode rune 计数；首行非标题时按全文计数（向后兼容非章节文本）。
///
/// 标题判定遵循 [ChapterTitleText.hasTitlePrefix] 的严格规则（`#` 后须空白、
/// TXT 列首无前导空白），不符合者按全文计数。
///
/// 用于 content.json 的 `ContentNode.characterCount` 持久化、概览统计、
/// 旧书库回填与 reconcile 重算，保证各处字数一致。`null`（未计算）与 `0`
/// （空章节）由调用方区分。
int characterCountOf(String text) {
  // 归一化行尾（\r\n / \r → \n）：经典 Mac 的 \r-only 行尾会让 bodyOf
  // 找不到 \n 而吞掉整段正文，统一成 \n 保证三种行尾一致。
  final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final body = ChapterTitleText.hasTitlePrefix(normalized)
      ? ChapterTitleText.bodyOf(normalized)
      : normalized;
  return body.replaceAll(RegExp(r'\s+'), '').runes.length;
}
