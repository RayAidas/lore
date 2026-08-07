import 'package:lore_domain/lore_domain.dart';

import '../ports/ai_chat_client.dart';
import 'generated_outline_parser.dart';

/// AI 大纲生成用例：按用户填写的主题/世界/人物/卷/章设定，分两步生成完整大纲。
///
/// - 第 1 步：生成「世界观 + 人物设定」，严格输出 `# 世界观`、`# 人物设定` 两节。
/// - 第 2 步：把第 1 步结果作为参考，生成「卷章大纲」，严格输出 `# 卷章大纲`，
///   保证卷章与世界/人物设定保持一致。
///
/// 两步都使用比默认更长的超时（180s）；prompt 要求每章仅一句话概括，压缩篇幅、
/// 降低小模型长输出截断的风险。
final class OutlineGenerationService {
  const OutlineGenerationService({required this.client});

  final AiChatClient client;
  final GeneratedOutlineParser _parser = const GeneratedOutlineParser();

  /// 分两步生成完整大纲，返回按分类拆分的 [GeneratedOutline]。
  ///
  /// [referenceText] 为可选的外部参考（如已关联的大纲），仅作设定与风格参考，
  /// 前置在第 1 步用户消息里。
  Future<GeneratedOutline> generate({
    required OutlineGenerationRequest request,
    String? referenceText,
    required WritingAgentConfig config,
    required String apiKey,
    Duration timeout = const Duration(seconds: 180),
  }) async {
    final step1 = await _complete(
      messages: [
        const AiChatMessage(
          role: AiChatRole.system,
          content: _worldCharacterSystemPrompt,
        ),
        AiChatMessage(
          role: AiChatRole.user,
          content: _step1UserContent(request, referenceText),
        ),
      ],
      config: config,
      apiKey: apiKey,
      timeout: timeout,
    );

    final split = _parser.splitStepOne(step1);

    final step2 = await _complete(
      messages: [
        const AiChatMessage(
          role: AiChatRole.system,
          content: _chaptersSystemPrompt,
        ),
        AiChatMessage(
          role: AiChatRole.user,
          content: _step2UserContent(request, step1),
        ),
      ],
      config: config,
      apiKey: apiKey,
      timeout: timeout,
    );

    return GeneratedOutline(
      worldSection: split.world ?? '',
      characterSection: split.characters ?? '',
      chaptersSection: step2.trim(),
    );
  }

  /// 第 1 步用户消息：主题 + 各非空设定字段 + 可选的外部参考（仅作参考）。
  String _step1UserContent(
    OutlineGenerationRequest request,
    String? referenceText,
  ) {
    final reference = _referenceOnlyBlock(referenceText);
    final buffer = StringBuffer()..writeln('小说主题/书名：${request.theme}');
    buffer.writeln('小说长度：${request.novelLength.label}');
    _appendIfPresent(buffer, label: '世界背景要求', value: request.worldSetting);
    _appendIfPresent(buffer, label: '人物设定要求', value: request.characterSetting);
    _appendIfPresent(buffer, label: '补充要求', value: request.extraPrompt);
    final content = buffer.toString().trim();
    return reference.isEmpty ? content : '$reference\n\n$content';
  }

  /// 第 2 步用户消息：主题 + 卷/章设定 + 补充要求，并把第 1 步的世界观与人物设定
  /// 作为「据此规划」的参考前置。
  String _step2UserContent(
    OutlineGenerationRequest request,
    String step1Output,
  ) {
    final reference = _buildOnBlock(step1Output);
    final buffer = StringBuffer()..writeln('小说主题/书名：${request.theme}');
    buffer.writeln('小说长度：${request.novelLength.label}');
    _appendIfPresent(buffer, label: '卷设定', value: request.volumeSetting);
    _appendIfPresent(buffer, label: '章设定', value: request.chapterSetting);
    _appendIfPresent(buffer, label: '补充要求', value: request.extraPrompt);
    final content = buffer.toString().trim();
    return reference.isEmpty ? content : '$reference\n\n$content';
  }

  void _appendIfPresent(
    StringBuffer buffer, {
    required String label,
    required String value,
  }) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return;
    }
    buffer
      ..writeln()
      ..writeln(label)
      ..writeln(trimmed);
  }

  /// 外部参考（如已关联的大纲）：仅作设定与风格参考，不要求模型输出它。
  String _referenceOnlyBlock(String? referenceText) {
    final text = referenceText?.trim();
    if (text == null || text.isEmpty) {
      return '';
    }
    return '参考材料（仅作设定与风格参考，不要改写或输出它）：\n$text';
  }

  /// 第 1 步产出：明确要求模型据此规划卷章大纲、保持一致。
  String _buildOnBlock(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    return '已生成的世界观与人物设定（请据此规划卷章大纲，保持一致）：\n$trimmed';
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
      throw AiRequestException('生成大纲失败：$error');
    }
  }
}

/// 第 1 步：世界观 + 人物设定。
const _worldCharacterSystemPrompt = '''
你是一位资深的小说设定师。请根据用户提供的小说主题、小说长度、世界背景要求与
人物设定要求，创作一份内容充实、逻辑自洽的世界观与人物设定。

请结合用户指定的小说长度（超短篇至超长篇）把握铺陈规模：篇幅越长，世界观与人物
设定越可详尽；超短篇/短篇则聚焦核心设定，避免过度铺陈。

请严格按以下 Markdown 结构输出，只输出这两个一级章节，不要添加任何解释或额外内容：

# 世界观
（在此展开世界背景：时代、地理、势力、力量体系、规则等）

# 人物设定
（在此逐人列出主要人物：姓名、身份、性格、目标、与主线的关系等）
''';

/// 第 2 步：卷章大纲。要求每章一句话概括，控制篇幅防截断。
const _chaptersSystemPrompt = '''
你是一位经验丰富的网文结构师。请基于用户提供的小说主题、小说长度、卷设定、
章设定，以及给定的世界观与人物设定，规划一份完整、连贯的卷章大纲。

请严格按以下 Markdown 结构输出，只输出卷章大纲，不要添加任何解释或额外内容：

# 卷章大纲

## 第一卷 卷名
### 第1章 章名
（用一句话概括本章核心情节）
### 第2章 章名
（用一句话概括本章核心情节）

## 第二卷 卷名
（同上逐卷展开）

若用户未指定卷或章数，请结合用户指定的小说长度规划合理的卷数与章数：超短篇/
短篇只需一两卷数章，中篇约两三卷，中长篇/长篇约三五卷以上，超长篇则需十余卷
并持续展开，同时保持章节之间因果与节奏连贯。
''';
