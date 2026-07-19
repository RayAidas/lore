/// 章节正文字数（含标题行）：去所有空白后按 Unicode rune 计数。
///
/// 用于 content.json 的 `ContentNode.characterCount` 持久化、概览统计、
/// 旧书库回填与 reconcile 重算，保证各处字数一致。`null`（未计算）与 `0`
/// （空章节）由调用方区分。
int characterCountOf(String text) =>
    text.replaceAll(RegExp(r'\s+'), '').runes.length;
