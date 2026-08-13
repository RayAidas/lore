/// 预置的快捷写作指令。
///
/// 每种动作对应一组固定的 system prompt（在 `lore_application` 的
/// `WritingAgentService` 中维护），面板据此渲染快捷按钮并决定上下文范围。
enum WritingAgentAction {
  /// 校对：检查错别字、病句与标点，返回修正后的文本。
  proofread,

  /// 润色/改写：保持原意优化表达，返回改写后的文本。
  polish,

  /// 总结：提炼要点，返回简洁摘要。
  summarize,

  /// 续写：基于给定正文继续写作，返回续写内容。
  continueWriting,

  /// 一致性检查：对照章节记忆与设定记忆，输出当前文字的矛盾清单，不改写正文。
  consistencyCheck,
}
