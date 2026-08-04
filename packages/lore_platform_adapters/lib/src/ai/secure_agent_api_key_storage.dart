import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:lore_application/lore_application.dart';

/// 基于 [FlutterSecureStorage] 的 API Key 安全存储适配器。
///
/// macOS 落到 Keychain、Android 落到 Keystore（EncryptedSharedPreferences），
/// 符合 `docs/designs/ai-agent.md`「API Key 不写入书库与普通配置文件」的要求。
final class SecureAgentApiKeyStorage implements AgentApiKeyStorage {
  SecureAgentApiKeyStorage();

  static const _key = 'lore.agent.api_key';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String? apiKey) async {
    if (apiKey == null || apiKey.isEmpty) {
      await _storage.delete(key: _key);
    } else {
      await _storage.write(key: _key, value: apiKey);
    }
  }
}
