import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_platform_adapters/lore_platform_adapters.dart';

final agentConfigRepositoryProvider = Provider<AgentConfigRepository>((ref) {
  return SharedPreferencesAgentConfigRepository();
});

final agentApiKeyStorageProvider = Provider<AgentApiKeyStorage>((ref) {
  return SecureAgentApiKeyStorage();
});

final agentConfigServiceProvider = Provider<AgentConfigService>((ref) {
  return AgentConfigService(
    configRepository: ref.watch(agentConfigRepositoryProvider),
    apiKeyStorage: ref.watch(agentApiKeyStorageProvider),
  );
});

final aiChatClientProvider = Provider<AiChatClient>((ref) {
  return HttpAiChatClient();
});

final writingAgentServiceProvider = Provider<WritingAgentService>((ref) {
  return WritingAgentService(client: ref.watch(aiChatClientProvider));
});

/// 写作 Agent 配置 + 是否已设置 API Key 的组合状态。
final class AgentConfigState {
  const AgentConfigState({required this.config, required this.hasApiKey});

  final WritingAgentConfig config;
  final bool hasApiKey;
}

/// 写作 Agent 配置的唯一可观察来源。
///
/// 配置（非敏感）存 SharedPreferences、API Key 存安全存储；两者组合成
/// [AgentConfigState]。采用 [AsyncNotifierProvider] 首次加载异步读取落库值。
final agentConfigProvider =
    AsyncNotifierProvider<AgentConfigController, AgentConfigState>(
      AgentConfigController.new,
    );

final class AgentConfigController extends AsyncNotifier<AgentConfigState> {
  @override
  Future<AgentConfigState> build() async {
    final service = ref.read(agentConfigServiceProvider);
    final config = await service.loadConfigOrDefault();
    final apiKey = await service.readApiKey();
    return AgentConfigState(
      config: config,
      hasApiKey: apiKey != null && apiKey.isNotEmpty,
    );
  }

  Future<void> setEnabled(bool value) =>
      _updateConfig((config) => config.copyWith(enabled: value));
  Future<void> setBaseUrl(String value) =>
      _updateConfig((config) => config.copyWith(baseUrl: value));
  Future<void> setModel(String value) =>
      _updateConfig((config) => config.copyWith(model: value));

  Future<void> setApiKey(String apiKey) async {
    final service = ref.read(agentConfigServiceProvider);
    await service.saveApiKey(apiKey);
    state = AsyncData(
      AgentConfigState(
        config: state.value?.config ?? WritingAgentConfig.defaults(),
        hasApiKey: apiKey.isNotEmpty,
      ),
    );
  }

  Future<void> clearApiKey() => setApiKey('');

  Future<void> _updateConfig(
    WritingAgentConfig Function(WritingAgentConfig) apply,
  ) async {
    final service = ref.read(agentConfigServiceProvider);
    final current = state.value?.config ?? WritingAgentConfig.defaults();
    final next = apply(current);
    await service.saveConfig(next);
    state = AsyncData(
      AgentConfigState(
        config: next,
        hasApiKey: state.value?.hasApiKey ?? false,
      ),
    );
  }
}
