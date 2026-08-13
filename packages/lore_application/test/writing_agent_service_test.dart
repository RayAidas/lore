import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:test/test.dart';

/// 记录调用参数并可配置结果的假客户端。
final class _FakeAiChatClient implements AiChatClient {
  List<AiChatMessage>? lastMessages;
  String? lastBaseUrl;
  String? lastApiKey;
  String? lastModel;
  Object? nextError;
  String nextText = '生成结果';

  @override
  Future<String> completeChat({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<AiChatMessage> messages,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    lastBaseUrl = baseUrl;
    lastApiKey = apiKey;
    lastModel = model;
    lastMessages = messages;
    final error = nextError;
    if (error != null) {
      throw error;
    }
    return nextText;
  }
}

void main() {
  const config = WritingAgentConfig(
    schemaVersion: WritingAgentConfig.schemaVersionCurrent,
    baseUrl: 'https://example.com/v1',
    model: 'test-model',
    enabled: true,
  );
  const apiKey = 'sk-test';

  late _FakeAiChatClient client;
  late WritingAgentService service;

  setUp(() {
    client = _FakeAiChatClient();
    service = WritingAgentService(client: client);
  });

  test('runAction sends system + user messages and returns text', () async {
    final result = await service.runAction(
      action: WritingAgentAction.polish,
      contextText: '这是一段需要润色的文字。',
      config: config,
      apiKey: apiKey,
    );

    expect(result, '生成结果');
    expect(client.lastBaseUrl, config.baseUrl);
    expect(client.lastApiKey, apiKey);
    expect(client.lastModel, config.model);
    expect(client.lastMessages, hasLength(2));
    expect(client.lastMessages![0].role, AiChatRole.system);
    expect(client.lastMessages![0].content, isNotEmpty);
    expect(client.lastMessages![1].role, AiChatRole.user);
    expect(client.lastMessages![1].content, '这是一段需要润色的文字。');
  });

  test('each action gets its own non-empty system prompt', () async {
    for (final action in WritingAgentAction.values) {
      await service.runAction(
        action: action,
        contextText: '正文',
        config: config,
        apiKey: apiKey,
      );
      final system = client.lastMessages![0].content;
      expect(system, isNotEmpty, reason: 'action $action should have a prompt');
    }
  });

  test('runAction prepends a labeled outline reference block', () async {
    await service.runAction(
      action: WritingAgentAction.continueWriting,
      contextText: '正文',
      referenceText: '【大纲.md】\n主角设定：林晚。',
      config: config,
      apiKey: apiKey,
    );

    final user = client.lastMessages![1].content;
    expect(user, contains('参考大纲'));
    expect(user, contains('主角设定：林晚。'));
    expect(user, contains('需要处理的文字：'));
    expect(user, contains('正文'));
    // 参考块在正文之前。
    expect(user.indexOf('参考大纲'), lessThan(user.indexOf('需要处理的文字')));
  });

  test('runAction without reference text has no outline block', () async {
    await service.runAction(
      action: WritingAgentAction.polish,
      contextText: '正文',
      config: config,
      apiKey: apiKey,
    );

    expect(client.lastMessages![1].content, '正文');
  });

  test('runAction prepends memory block before the outline reference', () async {
    await service.runAction(
      action: WritingAgentAction.continueWriting,
      contextText: '正文',
      referenceText: '大纲内容',
      memoryText: '第1章：林晚觉醒。',
      config: config,
      apiKey: apiKey,
    );

    final user = client.lastMessages![1].content;
    expect(user, contains('章节记忆'));
    expect(user, contains('第1章：林晚觉醒。'));
    expect(user, contains('参考大纲'));
    expect(user, contains('大纲内容'));
    // 章节记忆（长期一致）在前，参考大纲在后，正文在最后。
    expect(user.indexOf('章节记忆'), lessThan(user.indexOf('参考大纲')));
    expect(user.indexOf('参考大纲'), lessThan(user.indexOf('需要处理的文字')));
  });

  test('runAction with memory only has no outline block', () async {
    await service.runAction(
      action: WritingAgentAction.polish,
      contextText: '正文',
      memoryText: '第1章：林晚觉醒。',
      config: config,
      apiKey: apiKey,
    );

    final user = client.lastMessages![1].content;
    expect(user, contains('章节记忆'));
    expect(user, isNot(contains('参考大纲')));
    expect(user, contains('需要处理的文字'));
  });

  test('runAction prepends setting memory before chapter memory and outline',
      () async {
    await service.runAction(
      action: WritingAgentAction.consistencyCheck,
      contextText: '正文',
      settingText: '## 人物\n### 林晚\n- 身份：主角',
      memoryText: '第1章：林晚觉醒。',
      referenceText: '大纲内容',
      config: config,
      apiKey: apiKey,
    );

    final user = client.lastMessages![1].content;
    expect(user, contains('设定记忆'));
    expect(user, contains('### 林晚'));
    expect(user, contains('章节记忆'));
    expect(user, contains('参考大纲'));
    expect(user, contains('需要处理的文字'));
    // 顺序：设定记忆（结构化设定）< 章节记忆 < 参考大纲 < 正文。
    expect(user.indexOf('设定记忆'), lessThan(user.indexOf('章节记忆')));
    expect(user.indexOf('章节记忆'), lessThan(user.indexOf('参考大纲')));
    expect(user.indexOf('参考大纲'), lessThan(user.indexOf('需要处理的文字')));
  });

  test('runAction with setting memory only has no chapter or outline blocks',
      () async {
    await service.runAction(
      action: WritingAgentAction.continueWriting,
      contextText: '正文',
      settingText: '## 人物\n### 林晚',
      config: config,
      apiKey: apiKey,
    );

    final user = client.lastMessages![1].content;
    expect(user, contains('设定记忆'));
    expect(user, isNot(contains('章节记忆')));
    expect(user, isNot(contains('参考大纲')));
    expect(user, contains('需要处理的文字'));
  });

  test('runCustom includes the setting memory block before the instruction',
      () async {
    await service.runCustom(
      instruction: '核对一下设定',
      contextText: '上下文文字',
      settingText: '## 人物\n### 林晚',
      config: config,
      apiKey: apiKey,
    );

    final user = client.lastMessages![1].content;
    expect(user, contains('设定记忆'));
    expect(user.indexOf('设定记忆'), lessThan(user.indexOf('核对一下设定')));
  });

  test('runCustom includes the memory block before the instruction', () async {
    await service.runCustom(
      instruction: '继续写下一章',
      contextText: '上下文文字',
      memoryText: '第2章：她出现了。',
      config: config,
      apiKey: apiKey,
    );

    final user = client.lastMessages![1].content;
    expect(user, contains('章节记忆'));
    expect(user, contains('第2章：她出现了。'));
    expect(user.indexOf('章节记忆'), lessThan(user.indexOf('继续写下一章')));
  });

  test('runCustom prepends the outline reference before the instruction',
      () async {
    await service.runCustom(
      instruction: '改成更口语',
      contextText: '上下文文字',
      referenceText: '大纲内容',
      config: config,
      apiKey: apiKey,
    );

    final user = client.lastMessages![1].content;
    expect(user.indexOf('大纲内容'), lessThan(user.indexOf('改成更口语')));
    expect(user, contains('上下文文字'));
  });

  test('runCustom without reference text keeps the plain structure', () async {
    await service.runCustom(
      instruction: '改成更口语',
      contextText: '上下文文字',
      config: config,
      apiKey: apiKey,
    );

    final user = client.lastMessages![1].content;
    expect(user, startsWith('改成更口语'));
    expect(user, contains('上下文文字'));
  });

  test('runCustom embeds context with the instruction', () async {
    await service.runCustom(
      instruction: '改成更口语',
      contextText: '上下文文字',
      config: config,
      apiKey: apiKey,
    );

    final user = client.lastMessages![1].content;
    expect(user, contains('改成更口语'));
    expect(user, contains('上下文文字'));
  });

  test('runCustom without context sends the instruction alone', () async {
    await service.runCustom(
      instruction: '总结一下',
      contextText: '   ',
      config: config,
      apiKey: apiKey,
    );

    expect(client.lastMessages![1].content, '总结一下');
  });

  test('propagates AiRequestException as-is', () async {
    client.nextError = const AiRequestException('模型服务返回 429');

    await expectLater(
      service.runAction(
        action: WritingAgentAction.summarize,
        contextText: '正文',
        config: config,
        apiKey: apiKey,
      ),
      throwsA(isA<AiRequestException>().having(
        (e) => e.message,
        'message',
        '模型服务返回 429',
      )),
    );
  });

  test('wraps unexpected errors into AiRequestException', () async {
    client.nextError = StateError('boom');

    await expectLater(
      service.runCustom(
        instruction: 'x',
        contextText: 'y',
        config: config,
        apiKey: apiKey,
      ),
      throwsA(isA<AiRequestException>()),
    );
  });
}
