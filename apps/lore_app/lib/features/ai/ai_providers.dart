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

final linkedOutlinesRepositoryProvider = Provider<LinkedOutlinesRepository>(
  (ref) => const SharedPreferencesLinkedOutlinesRepository(),
);

final linkedOutlinesServiceProvider = Provider<LinkedOutlinesService>((ref) {
  return LinkedOutlinesService(
    repository: ref.watch(linkedOutlinesRepositoryProvider),
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

/// 每部小说已关联大纲的唯一可观察来源（SharedPreferences 落库，按小说持久化）。
final linkedOutlinesProvider =
    AsyncNotifierProvider<LinkedOutlinesController, NovelOutlineLinks>(
      LinkedOutlinesController.new,
    );

final class LinkedOutlinesController extends AsyncNotifier<NovelOutlineLinks> {
  @override
  Future<NovelOutlineLinks> build() async {
    return ref.read(linkedOutlinesServiceProvider).loadOrDefault();
  }

  Future<void> link(String novelId, String outlinePath) =>
      _update((links) => links.withLink(novelId, outlinePath));

  Future<void> unlink(String novelId, String outlinePath) =>
      _update((links) => links.withoutLink(novelId, outlinePath));

  Future<void> _update(
    NovelOutlineLinks Function(NovelOutlineLinks) apply,
  ) async {
    final service = ref.read(linkedOutlinesServiceProvider);
    final current = state.value ?? const NovelOutlineLinks.empty();
    final next = apply(current);
    await service.save(next);
    state = AsyncData(next);
  }
}
