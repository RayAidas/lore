import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_storage/lore_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dev.lore.app/library_access.test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('maps restored and selected access state', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      return {'token': '/tmp/library', 'displayPath': '/tmp/library'};
    });
    final gateway = MacOsLibraryAccessGateway(channel: channel);

    final restored = await gateway.restore();
    final selected = await gateway.select();

    expect(restored?.isPending, isFalse);
    expect(selected?.isPending, isTrue);
  });

  test('invokes commit discard and clear methods', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    final gateway = MacOsLibraryAccessGateway(channel: channel);

    await gateway.commit();
    await gateway.discard();
    await gateway.clear();

    expect(calls, [
      'commitLibraryDirectory',
      'discardLibraryDirectorySelection',
      'clearLibraryDirectory',
    ]);
  });

  test('maps platform permission errors', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'access_denied', message: 'denied');
    });
    final gateway = MacOsLibraryAccessGateway(channel: channel);

    await expectLater(
      gateway.restore(),
      throwsA(
        isA<LibraryAccessException>().having(
          (error) => error.failure.code,
          'code',
          LibraryFailureCode.permissionDenied,
        ),
      ),
    );
  });
}
