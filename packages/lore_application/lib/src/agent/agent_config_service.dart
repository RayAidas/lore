import 'package:lore_domain/lore_domain.dart';

import '../ports/agent_api_key_storage.dart';
import '../ports/agent_config_repository.dart';

/// 写作 Agent 配置的组合用例：把非敏感配置与安全存储的 API Key 两个端口
/// 拼成一个可供 UI 直接调用的服务。
final class AgentConfigService {
  const AgentConfigService({
    required this.configRepository,
    required this.apiKeyStorage,
  });

  final AgentConfigRepository configRepository;
  final AgentApiKeyStorage apiKeyStorage;

  Future<WritingAgentConfig> loadConfigOrDefault() async {
    final loaded = await configRepository.load();
    return loaded ?? WritingAgentConfig.defaults();
  }

  Future<void> saveConfig(WritingAgentConfig config) {
    return configRepository.save(config);
  }

  Future<String?> readApiKey() => apiKeyStorage.read();

  Future<void> saveApiKey(String? apiKey) => apiKeyStorage.write(apiKey);

  /// 是否已具备发起请求的全部条件：显式启用且 Key/地址/模型齐全。
  Future<bool> isReady() async {
    final config = await loadConfigOrDefault();
    if (!config.enabled) {
      return false;
    }
    final apiKey = await readApiKey();
    return apiKey != null &&
        apiKey.isNotEmpty &&
        config.baseUrl.isNotEmpty &&
        config.model.isNotEmpty;
  }
}
