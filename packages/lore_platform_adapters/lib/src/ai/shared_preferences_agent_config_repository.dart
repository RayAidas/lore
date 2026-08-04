import 'dart:async';
import 'dart:convert';

import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 基于 [SharedPreferences] 的写作 Agent 配置持久化适配器。
///
/// 命名约定与 [SharedPreferencesAppPreferencesRepository] 一致：单一 JSON 字符串
/// key（`lore.agent.config`），内嵌 `schemaVersion`；解析失败或版本不符时 [load]
/// 返回 `null`，让上层回退默认值。API Key 明文随配置一起存储（应用内）。
final class SharedPreferencesAgentConfigRepository
    implements AgentConfigRepository {
  SharedPreferencesAgentConfigRepository();

  static const _key = 'lore.agent.config';
  static const _schemaVersion = WritingAgentConfig.schemaVersionCurrent;

  // sync: true 让 save 时的 add 同步派发给监听者，避免异步广播在快速连续写入
  // 下丢失事件（配置仅在本进程内变更，同步派发安全）。
  final StreamController<WritingAgentConfig> _controller =
      StreamController<WritingAgentConfig>.broadcast(sync: true);

  @override
  Future<WritingAgentConfig?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_key);
    if (encoded == null) {
      return null;
    }
    try {
      final value = jsonDecode(encoded);
      if (value is! Map<String, Object?>) {
        return null;
      }
      if (value['schemaVersion'] != _schemaVersion) {
        return null;
      }
      final baseUrl = value['baseUrl'];
      final model = value['model'];
      final enabled = value['enabled'];
      if (baseUrl is! String || model is! String || enabled is! bool) {
        return null;
      }
      // apiKey 是后加字段，老 blob 缺失时容错为空字符串。
      final apiKey = value['apiKey'];
      return WritingAgentConfig(
        schemaVersion: _schemaVersion,
        baseUrl: baseUrl,
        model: model,
        enabled: enabled,
        apiKey: apiKey is String ? apiKey : '',
      );
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> save(WritingAgentConfig config) async {
    final store = await SharedPreferences.getInstance();
    await store.setString(_key, jsonEncode(_toJson(config)));
    _controller.add(config);
  }

  @override
  Stream<WritingAgentConfig> watch() => _controller.stream;

  Map<String, Object?> _toJson(WritingAgentConfig config) {
    return {
      'schemaVersion': _schemaVersion,
      'baseUrl': config.baseUrl,
      'model': config.model,
      'enabled': config.enabled,
      'apiKey': config.apiKey,
    };
  }
}
