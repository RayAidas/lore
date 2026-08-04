import 'package:lore_domain/lore_domain.dart';

import '../ports/agent_config_repository.dart';

/// 写作 Agent 配置的组合用例。
///
/// 配置与 API Key 均明文存于 [AgentConfigRepository]（应用内 SharedPreferences），
/// 不再走系统安全存储。UI 直接读写 [WritingAgentConfig.apiKey] 即可。
final class AgentConfigService {
  const AgentConfigService({required this.configRepository});

  final AgentConfigRepository configRepository;

  Future<WritingAgentConfig> loadConfigOrDefault() async {
    final loaded = await configRepository.load();
    return loaded ?? WritingAgentConfig.defaults();
  }

  Future<void> saveConfig(WritingAgentConfig config) {
    return configRepository.save(config);
  }

  /// 是否已具备发起请求的全部条件：显式启用且 Key/地址/模型齐全。
  Future<bool> isReady() async {
    final config = await loadConfigOrDefault();
    if (!config.enabled) {
      return false;
    }
    return config.apiKey.isNotEmpty &&
        config.baseUrl.isNotEmpty &&
        config.model.isNotEmpty;
  }
}
