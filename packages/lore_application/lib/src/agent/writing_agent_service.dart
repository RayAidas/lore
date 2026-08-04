import 'package:lore_domain/lore_domain.dart';

import '../ports/ai_chat_client.dart';

/// 写作 Agent 的执行用例：把预置/自定义指令与上下文文本组装成消息，
/// 调 [AiChatClient] 拿到结果文本。
///
/// system prompt 均要求「只返回结果文本、不做解释」，便于结果一键应用回文档。
final class WritingAgentService {
  const WritingAgentService({required this.client});

  final AiChatClient client;

  /// 对上下文执行预置动作，返回结果文本。
  Future<String> runAction({
    required WritingAgentAction action,
    required String contextText,
    required WritingAgentConfig config,
    required String apiKey,
    Duration timeout = const Duration(seconds: 60),
  }) {
    return _complete(
      messages: _messagesForAction(action, contextText),
      config: config,
      apiKey: apiKey,
      timeout: timeout,
    );
  }

  /// 执行用户自定义指令，同样携带当前上下文。
  Future<String> runCustom({
    required String instruction,
    required String contextText,
    required WritingAgentConfig config,
    required String apiKey,
    Duration timeout = const Duration(seconds: 60),
  }) {
    final content = contextText.trim().isEmpty
        ? instruction
        : '$instruction\n\n以下是参考上下文（仅作依据，不要求保留原文）：\n\n$contextText';
    return _complete(
      messages: [
        const AiChatMessage(role: AiChatRole.system, content: _customSystemPrompt),
        AiChatMessage(role: AiChatRole.user, content: content),
      ],
      config: config,
      apiKey: apiKey,
      timeout: timeout,
    );
  }

  Future<String> _complete({
    required List<AiChatMessage> messages,
    required WritingAgentConfig config,
    required String apiKey,
    required Duration timeout,
  }) async {
    try {
      return await client.completeChat(
        baseUrl: config.baseUrl,
        apiKey: apiKey,
        model: config.model,
        messages: messages,
        timeout: timeout,
      );
    } on AiRequestException {
      rethrow;
    } catch (error) {
      // 客户端/解析等非预期失败统一包装成可展示的错误。
      throw AiRequestException('请求模型失败：$error');
    }
  }

  List<AiChatMessage> _messagesForAction(
    WritingAgentAction action,
    String contextText,
  ) {
    return [
      AiChatMessage(
        role: AiChatRole.system,
        content: _systemPromptFor(action),
      ),
      AiChatMessage(role: AiChatRole.user, content: contextText),
    ];
  }

  String _systemPromptFor(WritingAgentAction action) {
    return switch (action) {
      WritingAgentAction.proofread => _proofreadPrompt,
      WritingAgentAction.polish => _polishPrompt,
      WritingAgentAction.summarize => _summarizePrompt,
      WritingAgentAction.continueWriting => _continueWritingPrompt,
    };
  }
}

/// 校对：返回修正后的完整文本。
const _proofreadPrompt = '''
你是一位严谨的中文校对编辑。检查以下文字的错别字、病句、标点与用词不当。
只返回修正后的完整文本，不要添加解释、注释或评论。若无修改，原样返回。''';

/// 润色：保持原意返回改写文本。
const _polishPrompt = '''
你是一位擅长中文文学写作的编辑。润色或改写以下文字，使其更流畅、生动，同时保持原意与风格。
只返回润色后的完整文本，不要添加解释。''';

/// 总结：返回简洁摘要。
const _summarizePrompt = '''
用简洁的中文总结以下内容，提炼核心信息与情节要点。尽量控制在 300 字以内。
只返回摘要本身，不要添加标题或解释。''';

/// 续写：保持风格接续原文。
const _continueWritingPrompt = '''
你是与原文同一作者的续写者。根据以下正文的风格、人物与情节，自然续写约 500 字。
只返回续写内容，不要复述或解释。''';

const _customSystemPrompt = '''
你是嵌入在写作应用中的写作助手。请直接执行用户的指令，结合提供的上下文给出有帮助的结果。
如需输出改写或续写文本，只返回正文本身。''';
