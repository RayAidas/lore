import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_platform_adapters/lore_platform_adapters.dart';

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

  test('invokes native no-replace rename', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return null;
    });
    final gateway = MacOsLibraryFileOperationsGateway(channel: channel);

    await gateway.rename(
      const LibraryAccess(
        token: '/tmp/library',
        displayPath: '/tmp/library',
        isPending: false,
      ),
      sourcePath: '旧名.md',
      targetPath: '新名.md',
    );

    expect(received?.method, 'renameLibraryEntry');
    expect(received?.arguments, {'sourcePath': '旧名.md', 'targetPath': '新名.md'});
  });

  test('maps native rename conflicts', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'name_conflict', message: 'exists');
    });
    final gateway = MacOsLibraryFileOperationsGateway(channel: channel);

    await expectLater(
      gateway.rename(
        const LibraryAccess(
          token: '/tmp/library',
          displayPath: '/tmp/library',
          isPending: false,
        ),
        sourcePath: '旧名.md',
        targetPath: '新名.md',
      ),
      throwsA(
        isA<LibraryOperationException>().having(
          (error) => error.failure.code,
          'code',
          LibraryFailureCode.alreadyExists,
        ),
      ),
    );
  });

  test('coordinates document replacement with an expected revision', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return true;
    });
    final gateway = MacOsLibraryFileOperationsGateway(channel: channel);

    final replaced = await gateway.replaceDocument(
      const LibraryAccess(
        token: '/tmp/library',
        displayPath: '/tmp/library',
        isPending: false,
      ),
      relativePath: '章节.txt',
      expectedRevision: 'revision-1',
      bytes: Uint8List.fromList([1, 2, 3]),
    );

    expect(replaced, isTrue);
    expect(received?.method, 'replaceLibraryDocument');
    expect(received?.arguments, {
      'relativePath': '章节.txt',
      'expectedRevision': 'revision-1',
      'bytes': Uint8List.fromList([1, 2, 3]),
    });
  });

  test('reports a coordinated replacement conflict', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => false);
    final gateway = MacOsLibraryFileOperationsGateway(channel: channel);

    final replaced = await gateway.replaceDocument(
      const LibraryAccess(
        token: '/tmp/library',
        displayPath: '/tmp/library',
        isPending: false,
      ),
      relativePath: '章节.txt',
      expectedRevision: 'revision-1',
      bytes: Uint8List(0),
    );

    expect(replaced, isFalse);
  });
}
