import 'package:lore_domain/lore_domain.dart';

/// 模型请求失败，携带可在 UI 展示的中文可读信息。
final class AiRequestException implements Exception {
  const AiRequestException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 第三方模型服务的抽象客户端端口。
///
/// 第一版只要求 OpenAI 风格的 Chat Completions 非流式调用（`stream: false`）；
/// 地址、Key、模型由调用方逐次传入，适配层无需持有配置状态。
abstract interface class AiChatClient {
  /// 发送一轮 [messages]，返回助手回复文本。失败抛 [AiRequestException]。
  Future<String> completeChat({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<AiChatMessage> messages,
    Duration timeout = const Duration(seconds: 60),
  });
}
