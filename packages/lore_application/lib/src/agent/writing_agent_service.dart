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
  ///
  /// [referenceText] 为可选参考材料（如关联的大纲），前置在用户消息里并明确
  /// 标注「仅作参考、不要改写」，让模型据此把握设定与风格，而不把它当作业目标。
  /// [memoryText] 为可选的章节记忆（历史章节摘要），置于参考大纲之前，让模型
  /// 与已写情节、人物、伏笔保持一致。
  /// [settingText] 为可选的设定记忆（人物/地点/时间线/伏笔结构化设定），置于
  /// 章节记忆之前，让模型优先按结构化设定核对一致性。
  Future<String> runAction({
    required WritingAgentAction action,
    required String contextText,
    String? referenceText,
    String? memoryText,
    String? settingText,
    required WritingAgentConfig config,
    required String apiKey,
    Duration timeout = const Duration(seconds: 60),
  }) {
    return _complete(
      messages: _messagesForAction(
        action,
        _composeUserContent(
          contextText,
          referenceText: referenceText,
          memoryText: memoryText,
          settingText: settingText,
        ),
      ),
      config: config,
      apiKey: apiKey,
      timeout: timeout,
    );
  }

  /// 执行用户自定义指令，同样携带当前上下文。
  Future<String> runCustom({
    required String instruction,
    required String contextText,
    String? referenceText,
    String? memoryText,
    String? settingText,
    required WritingAgentConfig config,
    required String apiKey,
    Duration timeout = const Duration(seconds: 60),
  }) {
    final blocks = _referenceBlocks(
      settingText: settingText,
      memoryText: memoryText,
      referenceText: referenceText,
    );
    final content = contextText.trim().isEmpty
        ? '$blocks$instruction'
        : '$blocks$instruction\n\n以下是参考上下文（仅作依据，不要求保留原文）：\n\n$contextText';
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

  /// 把可选的参考材料（章节记忆、大纲）拼进用户消息正文。无参考时原样返回正文。
  String _composeUserContent(
    String body, {
    String? referenceText,
    String? memoryText,
    String? settingText,
  }) {
    final blocks = _referenceBlocks(
      settingText: settingText,
      memoryText: memoryText,
      referenceText: referenceText,
    );
    if (blocks.isEmpty) {
      return body;
    }
    return '$blocks需要处理的文字：\n$body';
  }

  /// 前置参考块：设定记忆（结构化设定）在前，其后章节记忆（长期一致性），
  /// 参考大纲（设定/风格）在后；空块跳过。
  String _referenceBlocks({
    String? settingText,
    String? memoryText,
    String? referenceText,
  }) {
    final blocks = <String>[
      if (settingText?.trim().isNotEmpty ?? false) _settingBlock(settingText),
      if (memoryText?.trim().isNotEmpty ?? false) _memoryBlock(memoryText),
      if (referenceText?.trim().isNotEmpty ?? false)
        _referenceBlock(referenceText),
    ];
    return blocks.join('\n');
  }

  String _settingBlock(String? settingText) {
    final text = settingText?.trim();
    if (text == null || text.isEmpty) {
      return '';
    }
    return '设定记忆（本书人物/地点/时间线/伏笔的结构化设定，核对当前文字与之一致，不要改写或输出它）：\n$text';
  }

  String _memoryBlock(String? memoryText) {
    final text = memoryText?.trim();
    if (text == null || text.isEmpty) {
      return '';
    }
    return '章节记忆（本小说历史章节摘要，写作时保持与已有情节、人物、伏笔一致，不要改写或输出它）：\n$text';
  }

  String _referenceBlock(String? referenceText) {
    final text = referenceText?.trim();
    if (text == null || text.isEmpty) {
      return '';
    }
    return '参考大纲（仅作设定与风格参考，不要改写或输出它）：\n$text\n\n';
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
      WritingAgentAction.consistencyCheck => _consistencyCheckPrompt,
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

/// 一致性检查：对照章节记忆与设定记忆，只输出矛盾清单，不改写正文。
const _consistencyCheckPrompt = '''
你是一位严谨的小说连续性检查员。请把「需要处理的文字」与前置的「章节记忆」和
「设定记忆」逐项对照，找出当前文字中与已写情节、人物、称呼、身份、时间线、伏笔
或设定相矛盾的地方。

要求：
- 只输出矛盾清单；每条列出：矛盾点、涉及文字、依据（来自哪条章节记忆/设定记忆）。
- 不要改写、润色或复述正文。
- 若没有发现矛盾，只输出「未发现矛盾」。
- 若缺少章节记忆或设定记忆，先说明缺什么，再按现有材料检查。''';

const _customSystemPrompt = '''
你是嵌入在写作应用中的写作助手。请直接执行用户的指令，结合提供的上下文给出有帮助的结果。
如需输出改写或续写文本，只返回正文本身。''';
