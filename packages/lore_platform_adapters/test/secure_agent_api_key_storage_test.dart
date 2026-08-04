import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_platform_adapters/lore_platform_adapters.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SecureAgentApiKeyStorage storage;

  setUp(() {
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform({});
    storage = SecureAgentApiKeyStorage();
  });

  test('returns null when nothing stored', () async {
    expect(await storage.read(), isNull);
  });

  test('round-trips api key through secure storage', () async {
    await storage.write('sk-secret');
    expect(await storage.read(), 'sk-secret');
  });

  test('clears stored key on null write', () async {
    await storage.write('sk-secret');
    await storage.write(null);
    expect(await storage.read(), isNull);
  });

  test('clears stored key on empty write', () async {
    await storage.write('sk-secret');
    await storage.write('');
    expect(await storage.read(), isNull);
  });
}
