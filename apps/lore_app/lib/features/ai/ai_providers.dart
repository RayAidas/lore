import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_platform_adapters/lore_platform_adapters.dart';

final agentConfigRepositoryProvider = Provider<AgentConfigRepository>((ref) {
  return SharedPreferencesAgentConfigRepository();
});

final agentConfigServiceProvider = Provider<AgentConfigService>((ref) {
  return AgentConfigService(
    configRepository: ref.watch(agentConfigRepositoryProvider),
  );
});

final aiChatClientProvider = Provider<AiChatClient>((ref) {
  return HttpAiChatClient();
});

final writingAgentServiceProvider = Provider<WritingAgentService>((ref) {
  return WritingAgentService(client: ref.watch(aiChatClientProvider));
});

/// 写作 Agent 配置状态（含明文 API Key，均存于应用内 SharedPreferences）。
final class AgentConfigState {
  const AgentConfigState({required this.config});

  final WritingAgentConfig config;

  bool get hasApiKey => config.apiKey.isNotEmpty;
}

/// 写作 Agent 配置的唯一可观察来源。采用 [AsyncNotifierProvider] 首次加载
/// 异步读取落库值。
final agentConfigProvider =
    AsyncNotifierProvider<AgentConfigController, AgentConfigState>(
      AgentConfigController.new,
    );

final class AgentConfigController extends AsyncNotifier<AgentConfigState> {
  @override
  Future<AgentConfigState> build() async {
    final service = ref.read(agentConfigServiceProvider);
    final config = await service.loadConfigOrDefault();
    return AgentConfigState(config: config);
  }

  Future<void> setEnabled(bool value) =>
      _updateConfig((config) => config.copyWith(enabled: value));
  Future<void> setBaseUrl(String value) =>
      _updateConfig((config) => config.copyWith(baseUrl: value));
  Future<void> setModel(String value) =>
      _updateConfig((config) => config.copyWith(model: value));
  Future<void> setApiKey(String apiKey) =>
      _updateConfig((config) => config.copyWith(apiKey: apiKey));
  Future<void> clearApiKey() =>
      _updateConfig((config) => config.copyWith(apiKey: ''));

  Future<void> _updateConfig(
    WritingAgentConfig Function(WritingAgentConfig) apply,
  ) async {
    final service = ref.read(agentConfigServiceProvider);
    final current = state.value?.config ?? WritingAgentConfig.defaults();
    final next = apply(current);
    await service.saveConfig(next);
    state = AsyncData(AgentConfigState(config: next));
  }
}
