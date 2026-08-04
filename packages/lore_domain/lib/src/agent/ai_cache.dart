/// 一次 AI 请求的来源类型。
enum AiCacheEntryKind {
  /// 预置快捷指令（校对/润色/总结/续写）。
  action,

  /// 用户自定义指令。
  custom,
}

/// AI 请求的一条缓存记录（精简元信息 + 输出，不含上下文正文全文）。
///
/// 落盘在小说目录下的 `.cache` 文件（经存储会话字节 API）。`prompt` 对
/// action 记录存枚举名（如 `polish`），对 custom 记录存指令原文；展示层据此
/// 显示中文标签或指令，并支持「重跑」。
final class AiCacheEntry {
  const AiCacheEntry({
    required this.timestampMillis,
    required this.kind,
    required this.prompt,
    required this.contextSummary,
    required this.output,
  });

  final int timestampMillis;
  final AiCacheEntryKind kind;

  /// action：`WritingAgentAction` 的枚举名；custom：指令原文。
  final String prompt;

  /// 发送时的上下文概要（如「当前章节正文 · 1,234 字」+ 关联大纲数）。
  final String contextSummary;

  /// 模型返回的完整结果文本。
  final String output;
}

/// 某部小说的 AI 请求缓存（按时间顺序追加）。
final class AiCache {
  const AiCache(this.entries);

  const AiCache.empty() : entries = const [];

  final List<AiCacheEntry> entries;

  AiCache append(AiCacheEntry entry) => AiCache([...entries, entry]);

  /// 移除指定下标的记录（`entries` 按时间正序）。
  AiCache removeAt(int index) {
    if (index < 0 || index >= entries.length) {
      return this;
    }
    return AiCache([...entries]..removeAt(index));
  }

  AiCache clear() => const AiCache.empty();
}
