import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_platform_adapters/lore_platform_adapters.dart';

import '../library/library_providers.dart';

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

/// AI 请求缓存服务：经原始存储会话读写小说目录下的 `.cache` 文件。
final aiCacheServiceProvider = Provider<AiCacheService>((ref) {
  return AiCacheService(
    storageFactory: ref.watch(libraryStorageFactoryProvider),
  );
});

final writingAgentServiceProvider = Provider<WritingAgentService>((ref) {
  return WritingAgentService(client: ref.watch(aiChatClientProvider));
});

/// AI 大纲生成服务：分两步生成完整大纲并解析为分类结果。
final outlineGenerationServiceProvider = Provider<OutlineGenerationService>((
  ref,
) {
  return OutlineGenerationService(client: ref.watch(aiChatClientProvider));
});

/// AI 章节记忆生成服务：读小说全部章节、分批生成逐章摘要文档。
final memoryGenerationServiceProvider = Provider<MemoryGenerationService>((ref) {
  return MemoryGenerationService(
    client: ref.watch(aiChatClientProvider),
    documentRepository: ref.watch(documentRepositoryProvider),
  );
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
  /// 一键应用内置模型预设：同时写入接口地址与模型名。
  Future<void> applyPreset(String baseUrl, String model) => _updateConfig(
    (config) => config.copyWith(baseUrl: baseUrl, model: model),
  );
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
