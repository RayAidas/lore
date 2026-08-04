/// API Key 的设备安全存储端口。
///
/// 按 `docs/designs/ai-agent.md`，API Key 存于 macOS Keychain / Android Keystore，
/// 不写入书库与普通配置文件。写 `null` 表示清除。
abstract interface class AgentApiKeyStorage {
  Future<String?> read();

  /// [apiKey] 为 null 时删除已存 Key。
  Future<void> write(String? apiKey);
}
