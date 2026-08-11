/// 章节记忆文档的固定文件名、头部与元数据辅助。
///
/// 记忆文档是小说根目录下一个可见的 Markdown 文件，供用户审阅修正，也供写作
/// 助手作为「历史章节记忆」注入上下文。文档头（一级标题 + 元数据行）由
/// [MemoryGenerationService] 固定生成（不经模型），其中「基于 N 章生成」的元数据
/// 行供面板比对当前章节数，提示记忆是否落后。
library;

/// 记忆文档文件名主干；扩展名 `.md` 由存储层自动补全。
const String chapterMemoryDocName = '小说记忆';

/// 组装记忆文档头部：一级标题 + 元数据行（基于 N 章生成 · 日期）。
///
/// [now] 仅供测试注入；默认取当前时间。
String formatMemoryHeader(int chapterCount, {DateTime? now}) {
  final date = _formatDate(now ?? DateTime.now());
  return '# 章节记忆\n> 基于 $chapterCount 章生成 · $date';
}

/// 从记忆文档文本解析「基于 N 章生成」的章节数；未命中返回 `null`。
int? parseMemoryChapterCount(String text) {
  final match = RegExp(r'基于 (\d+) 章生成').firstMatch(text);
  return match == null ? null : int.parse(match.group(1)!);
}

String _formatDate(DateTime time) {
  final year = time.year.toString().padLeft(4, '0');
  final month = time.month.toString().padLeft(2, '0');
  final day = time.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
