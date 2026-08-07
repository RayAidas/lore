import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:test/test.dart';

/// 按序返回预设文本、记录每次调用参数的假客户端。
final class _FakeAiChatClient implements AiChatClient {
  _FakeAiChatClient(this._responses);

  final List<String> _responses;
  final List<({List<AiChatMessage> messages, Duration timeout})> calls = [];
  Object? nextError;

  @override
  Future<String> completeChat({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<AiChatMessage> messages,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final error = nextError;
    if (error != null) {
      throw error;
    }
    calls.add((messages: messages, timeout: timeout));
    return _responses.removeAt(0);
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

  const request = OutlineGenerationRequest(
    theme: '龙渊纪元',
    worldSetting: '东方玄幻，灵气复苏',
    characterSetting: '主角林晚，反派丞相',
    volumeSetting: '5 卷',
    chapterSetting: '每卷 8-12 章',
    extraPrompt: '结局要有反转',
  );

  const step1Output = '''
# 世界观
灵气复苏的东方世界。

# 人物设定
林晚：孤僻天才。
''';

  const step2Output = '''
# 卷章大纲

## 第一卷 初入江湖
### 第1章 觉醒
（一句话情节）
''';

  test(
    'makes exactly two calls with 180s timeout and returns split result',
    () async {
      final client = _FakeAiChatClient([step1Output, step2Output]);
      final service = OutlineGenerationService(client: client);

      final result = await service.generate(
        request: request,
        config: config,
        apiKey: apiKey,
      );

      expect(client.calls, hasLength(2));
      expect(
        client.calls.every(
          (call) => call.timeout == const Duration(seconds: 180),
        ),
        isTrue,
      );
      // 第 1 步产出解析为世界观与人物设定；第 2 步产出作为卷章大纲。
      expect(result.worldSection, contains('灵气复苏的东方世界'));
      expect(result.characterSection, contains('林晚：孤僻天才'));
      expect(result.chaptersSection, contains('第一卷 初入江湖'));
    },
  );

  test(
    'step-one user message carries theme, world and character settings',
    () async {
      final client = _FakeAiChatClient([step1Output, step2Output]);
      final service = OutlineGenerationService(client: client);

      await service.generate(request: request, config: config, apiKey: apiKey);

      final step1User = client.calls[0].messages[1].content;
      expect(client.calls[0].messages[0].role, AiChatRole.system);
      expect(client.calls[0].messages[0].content, isNotEmpty);
      expect(step1User, contains('龙渊纪元'));
      expect(step1User, contains('东方玄幻，灵气复苏'));
      expect(step1User, contains('主角林晚，反派丞相'));
      // 卷/章设定属于第 2 步，不应出现在第 1 步。
      expect(step1User, isNot(contains('5 卷')));
    },
  );

  test('step-one includes external reference text as reference only', () async {
    final client = _FakeAiChatClient([step1Output, step2Output]);
    final service = OutlineGenerationService(client: client);

    await service.generate(
      request: request,
      referenceText: '【大纲.md】旧作风格参考',
      config: config,
      apiKey: apiKey,
    );

    final step1User = client.calls[0].messages[1].content;
    expect(step1User, contains('参考材料'));
    expect(step1User, contains('旧作风格参考'));
    expect(step1User.indexOf('参考材料'), lessThan(step1User.indexOf('龙渊纪元')));
  });

  test(
    'step-two user message carries volume/chapter settings and step-one output',
    () async {
      final client = _FakeAiChatClient([step1Output, step2Output]);
      final service = OutlineGenerationService(client: client);

      await service.generate(request: request, config: config, apiKey: apiKey);

      final step2User = client.calls[1].messages[1].content;
      expect(step2User, contains('5 卷'));
      expect(step2User, contains('每卷 8-12 章'));
      expect(step2User, contains('结局要有反转'));
      // 第 1 步产出作为参考传入第 2 步，保证卷章与世界/人物一致。
      expect(step2User, contains('已生成的世界观与人物设定'));
      expect(step2User, contains('灵气复苏的东方世界'));
      // 卷/章设定不在第 1 步、主题不重复出现于第 2 步的设定块。
      expect(step2User, contains('龙渊纪元'));
    },
  );

  test('novel length appears in both step messages', () async {
    const lengthRequest = OutlineGenerationRequest(
      theme: '龙渊纪元',
      novelLength: NovelLength.epic,
    );
    final client = _FakeAiChatClient([step1Output, step2Output]);
    final service = OutlineGenerationService(client: client);

    await service.generate(
      request: lengthRequest,
      config: config,
      apiKey: apiKey,
    );

    // 第 1 步据此把握世界观/人物铺陈规模，第 2 步据此规划卷数与章数。
    expect(client.calls[0].messages[1].content, contains('小说长度：超长篇'));
    expect(client.calls[1].messages[1].content, contains('小说长度：超长篇'));
  });

  test('novel length defaults to 中长篇', () async {
    final client = _FakeAiChatClient([step1Output, step2Output]);
    final service = OutlineGenerationService(client: client);

    await service.generate(request: request, config: config, apiKey: apiKey);

    expect(client.calls[0].messages[1].content, contains('小说长度：中长篇'));
  });

  test(
    'empty world and character headings fall back to world section',
    () async {
      const unparsed = '模型没有按标题输出。';
      final client = _FakeAiChatClient([unparsed, step2Output]);
      final service = OutlineGenerationService(client: client);

      final result = await service.generate(
        request: request,
        config: config,
        apiKey: apiKey,
      );

      expect(result.worldSection, unparsed);
      expect(result.characterSection, isEmpty);
    },
  );

  test('propagates AiRequestException as-is', () async {
    final client = _FakeAiChatClient([step1Output, step2Output])
      ..nextError = const AiRequestException('模型服务返回 429');
    final service = OutlineGenerationService(client: client);

    await expectLater(
      service.generate(request: request, config: config, apiKey: apiKey),
      throwsA(
        isA<AiRequestException>().having(
          (e) => e.message,
          'message',
          '模型服务返回 429',
        ),
      ),
    );
  });

  test('wraps unexpected errors into AiRequestException', () async {
    final client = _FakeAiChatClient([step1Output, step2Output])
      ..nextError = StateError('boom');
    final service = OutlineGenerationService(client: client);

    await expectLater(
      service.generate(request: request, config: config, apiKey: apiKey),
      throwsA(isA<AiRequestException>()),
    );
  });
}
