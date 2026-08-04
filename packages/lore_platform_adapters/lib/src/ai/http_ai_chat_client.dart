import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';

/// 基于 `package:http` 的 OpenAI 风格 Chat Completions 适配器。
///
/// 调用 `$baseUrl/chat/completions`（非流式），解析 `choices[0].message.content`
/// 返回助手文本；HTTP 非 2xx、超时、坏响应均抛 [AiRequestException]。
/// 请求数据会发送到第三方模型服务——是否可接受由用户配置该服务决定。
final class HttpAiChatClient implements AiChatClient {
  HttpAiChatClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<String> completeChat({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<AiChatMessage> messages,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final url = Uri.parse('${_trimTrailingSlash(baseUrl)}/chat/completions');
    final body = jsonEncode({
      'model': model,
      'messages': [
        for (final message in messages)
          {'role': message.role.name, 'content': message.content},
      ],
      'stream': false,
    });

    late final http.Response response;
    try {
      response = await _client
          .post(
            url,
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: body,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const AiRequestException('请求模型超时，请稍后重试');
    } on http.ClientException catch (error) {
      throw AiRequestException('网络错误：${error.message}');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiRequestException(
        '模型服务返回 ${response.statusCode}：${_responseSnippet(response.body)}',
      );
    }

    final String content;
    try {
      content = _parseContent(response.body);
    } catch (error) {
      throw AiRequestException('模型响应格式异常：$error');
    }
    if (content.isEmpty) {
      throw const AiRequestException('模型返回了空结果');
    }
    return content;
  }

  String _trimTrailingSlash(String url) {
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  String _responseSnippet(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return '空响应';
    }
    return trimmed.length <= 160 ? trimmed : '${trimmed.substring(0, 160)}…';
  }

  String _parseContent(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('响应不是 JSON 对象');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const FormatException('缺少 choices');
    }
    final first = choices.first;
    if (first is! Map<String, Object?>) {
      throw const FormatException('choices[0] 结构异常');
    }
    final message = first['message'];
    if (message is! Map<String, Object?>) {
      throw const FormatException('choices[0].message 缺失');
    }
    final content = message['content'];
    if (content is! String) {
      throw const FormatException('choices[0].message.content 缺失');
    }
    return content;
  }
}
