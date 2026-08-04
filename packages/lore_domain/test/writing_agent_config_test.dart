import 'package:lore_domain/lore_domain.dart';
import 'package:test/test.dart';

void main() {
  test('defaults are disabled with OpenAI-compatible base url', () {
    final config = WritingAgentConfig.defaults();
    expect(config.enabled, isFalse);
    expect(config.baseUrl, 'https://api.openai.com/v1');
    expect(config.model, isNotEmpty);
    expect(config.schemaVersion, WritingAgentConfig.schemaVersionCurrent);
  });

  test('copyWith overrides only the given fields', () {
    final original = WritingAgentConfig.defaults();
    final next = original.copyWith(model: 'deepseek-chat', enabled: true);

    expect(next.model, 'deepseek-chat');
    expect(next.enabled, isTrue);
    expect(next.baseUrl, original.baseUrl);
    expect(next.schemaVersion, original.schemaVersion);
  });
}
