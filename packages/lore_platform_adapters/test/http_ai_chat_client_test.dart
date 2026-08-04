import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_platform_adapters/lore_platform_adapters.dart';

void main() {
  const messages = [
    AiChatMessage(role: AiChatRole.system, content: '你是助手'),
    AiChatMessage(role: AiChatRole.user, content: '你好'),
  ];

  late Uri? lastUri;
  late Map<String, String>? lastHeaders;
  late Map<String, Object?>? lastBody;

  MockClient clientWith(http.Response Function() responder) {
    return MockClient((request) async {
      lastUri = request.url;
      lastHeaders = request.headers;
      lastBody = jsonDecode(request.body) as Map<String, Object?>;
      return responder();
    });
  }

  setUp(() {
    lastUri = null;
    lastHeaders = null;
    lastBody = null;
  });

  test('posts to baseUrl/chat/completions with auth and parses content',
      () async {
    final client = HttpAiChatClient(
      client: clientWith(
        () => http.Response(
          jsonEncode({
            'choices': [
              {'message': {'role': 'assistant', 'content': '结果文本'}},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );

    final text = await client.completeChat(
      baseUrl: 'https://example.com/v1/',
      apiKey: 'sk-abc',
      model: 'm1',
      messages: messages,
    );

    expect(text, '结果文本');
    expect(lastUri.toString(), 'https://example.com/v1/chat/completions');
    expect(lastHeaders!['Authorization'], 'Bearer sk-abc');
    expect(lastBody!['model'], 'm1');
    expect(lastBody!['stream'], isFalse);
    final sent = (lastBody!['messages'] as List).cast<Map<String, Object?>>();
    expect(sent[0]['role'], 'system');
    expect(sent[0]['content'], '你是助手');
  });

  /// 返回合法成功体的 MockClient，仅用于校验请求 URL。
  MockClient okResponder() {
    return clientWith(
      () => http.Response(
        jsonEncode({
          'choices': [
            {'message': {'role': 'assistant', 'content': 'ok'}},
          ],
        }),
        200,
      ),
    );
  }

  test('accepts a bare domain base url (deepseek style)', () async {
    final client = HttpAiChatClient(client: okResponder());
    await client.completeChat(
      baseUrl: 'https://api.deepseek.com',
      apiKey: 'sk',
      model: 'm1',
      messages: messages,
    );
    expect(lastUri.toString(), 'https://api.deepseek.com/chat/completions');
  });

  test('normalizes a base url that already ends with /chat/completions', () async {
    final client = HttpAiChatClient(client: okResponder());
    // 用户误把完整 endpoint 填进接口地址：不应拼成重复段。
    await client.completeChat(
      baseUrl: 'https://api.deepseek.com/v1/chat/completions',
      apiKey: 'sk',
      model: 'm1',
      messages: messages,
    );
    expect(lastUri.toString(), 'https://api.deepseek.com/v1/chat/completions');

    await client.completeChat(
      baseUrl: 'https://api.deepseek.com/chat/completions',
      apiKey: 'sk',
      model: 'm1',
      messages: messages,
    );
    expect(lastUri.toString(), 'https://api.deepseek.com/chat/completions');
  });

  test('throws readable error on non-2xx status', () async {
    final client = HttpAiChatClient(
      client: clientWith(
        () => http.Response('invalid key', 401),
      ),
    );

    await expectLater(
      client.completeChat(
        baseUrl: 'https://example.com/v1',
        apiKey: 'bad',
        model: 'm1',
        messages: messages,
      ),
      throwsA(
        isA<AiRequestException>().having(
          (e) => e.message,
          'message',
          contains('401'),
        ),
      ),
    );
  });

  test('404 error hints that the base url may include the endpoint', () async {
    final client = HttpAiChatClient(
      client: clientWith(
        () => http.Response('not found', 404),
      ),
    );

    await expectLater(
      client.completeChat(
        baseUrl: 'https://api.deepseek.com',
        apiKey: 'sk',
        model: 'm1',
        messages: messages,
      ),
      throwsA(
        isA<AiRequestException>().having(
          (e) => e.message,
          'message',
          contains('404'),
        ).having((e) => e.message, 'hint', contains('/chat/completions')),
      ),
    );
  });

  test('throws on malformed success body', () async {
    final client = HttpAiChatClient(
      client: clientWith(() => http.Response('{oops', 200)),
    );

    await expectLater(
      client.completeChat(
        baseUrl: 'https://example.com/v1',
        apiKey: 'sk',
        model: 'm1',
        messages: messages,
      ),
      throwsA(isA<AiRequestException>()),
    );
  });

  test('throws when choices are empty', () async {
    final client = HttpAiChatClient(
      client: clientWith(
        () => http.Response(jsonEncode({'choices': <Object>[]}), 200),
      ),
    );

    await expectLater(
      client.completeChat(
        baseUrl: 'https://example.com/v1',
        apiKey: 'sk',
        model: 'm1',
        messages: messages,
      ),
      throwsA(isA<AiRequestException>()),
    );
  });
}
