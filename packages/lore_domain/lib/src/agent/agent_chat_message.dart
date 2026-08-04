/// Chat Completions 消息的角色。
enum AiChatRole { system, user, assistant }

/// 一次模型请求中的单条消息。
///
/// 结构对齐 OpenAI 风格 Chat Completions 的 `{role, content}`，供应用层
/// 组装请求与平台适配层序列化共用；领域层只定义值类型，不含网络逻辑。
final class AiChatMessage {
  const AiChatMessage({required this.role, required this.content});

  final AiChatRole role;
  final String content;
}
