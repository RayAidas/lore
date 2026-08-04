/// 写作 Agent 的模型服务配置。
///
/// 只承载非敏感信息：接口地址、模型名、启用开关。API Key 单独走设备安全存储
/// （macOS Keychain / Android Keystore，见 `AgentApiKeyStorage` 端口），不进入
/// 本配置，避免与普通配置一同明文落盘。
final class WritingAgentConfig {
  const WritingAgentConfig({
    required this.schemaVersion,
    required this.baseUrl,
    required this.model,
    required this.enabled,
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

  WritingAgentConfig copyWith({
    String? baseUrl,
    String? model,
    bool? enabled,
  }) {
    return WritingAgentConfig(
      schemaVersion: schemaVersion,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      enabled: enabled ?? this.enabled,
    );
  }
}
