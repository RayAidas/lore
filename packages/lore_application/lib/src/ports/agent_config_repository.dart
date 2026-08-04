import 'package:lore_domain/lore_domain.dart';

/// 写作 Agent 配置的持久化端口。
///
/// 实现负责把 [WritingAgentConfig]（含明文 API Key）写入可重建的本地存储（如
/// SharedPreferences），并通过 [watch] 暴露变更流。
abstract interface class AgentConfigRepository {
  Future<WritingAgentConfig?> load();

  Future<void> save(WritingAgentConfig config);

  /// 在 [save] 之后推送最新配置；首条事件由实现决定是否立即发出当前值。
  Stream<WritingAgentConfig> watch();
}
