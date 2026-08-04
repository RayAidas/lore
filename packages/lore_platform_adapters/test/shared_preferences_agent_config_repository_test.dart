import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_platform_adapters/lore_platform_adapters.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferencesAgentConfigRepository repository;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repository = SharedPreferencesAgentConfigRepository();
  });

  test('returns null when nothing stored', () async {
    expect(await repository.load(), isNull);
  });

  test('round-trips config including plaintext api key', () async {
    final original = WritingAgentConfig.defaults().copyWith(
      baseUrl: 'https://example.com/v1',
      model: 'deepseek-chat',
      enabled: true,
      apiKey: 'sk-plaintext',
    );

    await repository.save(original);

    final loaded = await repository.load();
    expect(loaded, isNotNull);
    expect(loaded!.baseUrl, 'https://example.com/v1');
    expect(loaded.model, 'deepseek-chat');
    expect(loaded.enabled, isTrue);
    expect(loaded.apiKey, 'sk-plaintext');
    expect(loaded.schemaVersion, WritingAgentConfig.schemaVersionCurrent);
  });

  test('tolerates a legacy blob without the apiKey field', () async {
    SharedPreferences.setMockInitialValues({
      'lore.agent.config': jsonEncode({
        'schemaVersion': WritingAgentConfig.schemaVersionCurrent,
        'baseUrl': 'https://example.com/v1',
        'model': 'm',
        'enabled': true,
      }),
    });
    final loaded = await repository.load();
    expect(loaded, isNotNull);
    expect(loaded!.apiKey, isEmpty);
  });

  test('returns null for a corrupted blob', () async {
    SharedPreferences.setMockInitialValues({
      'lore.agent.config': 'not-json',
    });
    expect(await repository.load(), isNull);
  });

  test('returns null for a wrong schema version', () async {
    SharedPreferences.setMockInitialValues({
      'lore.agent.config': jsonEncode({
        'schemaVersion': 99,
        'baseUrl': 'https://example.com/v1',
        'model': 'm',
        'enabled': true,
      }),
    });
    expect(await repository.load(), isNull);
  });

  test('returns null when required fields are missing', () async {
    SharedPreferences.setMockInitialValues({
      'lore.agent.config': jsonEncode({
        'schemaVersion': WritingAgentConfig.schemaVersionCurrent,
        'baseUrl': 'https://example.com/v1',
      }),
    });
    expect(await repository.load(), isNull);
  });

  test('watch emits after save', () async {
    final events = <WritingAgentConfig>[];
    final subscription = repository.watch().listen(events.add);
    await repository.save(WritingAgentConfig.defaults());
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(1));
    expect(events.single.enabled, isFalse);

    await subscription.cancel();
  });
}
