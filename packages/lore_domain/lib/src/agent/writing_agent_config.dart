/// 写作 Agent 的模型服务配置。
///
/// 承载接口地址、模型名、启用开关与 API Key。Key 与普通配置一并**明文**存储在
/// 应用内（SharedPreferences），这是有意为之的取舍：为了跨平台简单与离线可用，
/// 牺牲了系统安全存储（Keychain/Keystore）的加密隔离。使用方应了解明文存储的
/// 风险，不要在共享/备份环境中存放高价值 Key。
final class WritingAgentConfig {
  const WritingAgentConfig({
    required this.schemaVersion,
    required this.baseUrl,
    required this.model,
    required this.enabled,
    this.apiKey = '',
  });

  static const schemaVersionCurrent = 1;

  /// 开箱默认：OpenAI 兼容地址与轻量模型；`enabled` 为 false，用户填好 Key 并
  /// 显式启用后才生效（见 `docs/designs/ai-agent.md` 的启用方式）。
  factory WritingAgentConfig.defaults() => const WritingAgentConfig(
    schemaVersion: schemaVersionCurrent,
    baseUrl: 'https://api.openai.com/v1',
    model: 'gpt-4o-mini',
    enabled: false,
  );

  final int schemaVersion;

  /// OpenAI 风格 Chat Completions 接口地址（不含 `/chat/completions` 后缀，
  /// 由调用方拼接），例如 `https://api.openai.com/v1` 或兼容服务自定义地址。
  final String baseUrl;

  /// 模型标识，例如 `gpt-4o-mini`、`deepseek-chat`。
  final String model;

  /// 总开关：为 false 时面板提示未启用，不发起请求。
  final bool enabled;

  /// 第三方模型服务的 API Key，明文存于应用内配置（非系统安全存储）。
  final String apiKey;

  WritingAgentConfig copyWith({
    String? baseUrl,
    String? model,
    bool? enabled,
    String? apiKey,
  }) {
    return WritingAgentConfig(
      schemaVersion: schemaVersion,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      enabled: enabled ?? this.enabled,
      apiKey: apiKey ?? this.apiKey,
    );
  }
}
