import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_platform_adapters/lore_platform_adapters.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const accessChannel = MethodChannel('lore.test.android.access');
  const storageChannel = MethodChannel('lore.test.android.storage');

  tearDown(() {
    messenger.setMockMethodCallHandler(accessChannel, null);
    messenger.setMockMethodCallHandler(storageChannel, null);
  });

  test('maps selected SAF access to the Android backend', () async {
    messenger.setMockMethodCallHandler(
      accessChannel,
      (_) async => {
        'token': 'content://provider/tree/root',
        'displayPath': 'root',
      },
    );
    final gateway = AndroidSafLibraryAccessGateway(channel: accessChannel);

    final access = await gateway.select();

    expect(access?.backend, LibraryBackendKind.androidSaf);
    expect(access?.isPending, isTrue);
  });

  test('create invokes native create with the requested name', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(accessChannel, (call) async {
      received = call;
      return {'token': 'content://provider/tree/child', 'displayPath': '我的书库'};
    });
    final gateway = AndroidSafLibraryAccessGateway(channel: accessChannel);

    final access = await gateway.create(name: '我的书库');

    expect(received?.method, 'createLibraryDirectory');
    expect(received?.arguments, {'name': '我的书库'});
    expect(access?.backend, LibraryBackendKind.androidSaf);
    expect(access?.isPending, isTrue);
  });

  test('maps create name conflicts', () async {
    messenger.setMockMethodCallHandler(accessChannel, (call) async {
      throw PlatformException(code: 'already_exists', message: 'exists');
    });
    final gateway = AndroidSafLibraryAccessGateway(channel: accessChannel);

    await expectLater(
      gateway.create(name: '我的书库'),
      throwsA(
        isA<LibraryAccessException>().having(
          (error) => error.failure.code,
          'code',
          LibraryFailureCode.alreadyExists,
        ),
      ),
    );
  });

  test('maps SAF storage entries and revision conflicts', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(storageChannel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'getCapabilities' => {
          'atomicReplace': false,
          'move': true,
          'rename': true,
          'caseSensitive': true,
        },
        'list' => [
          {'path': '正文/第一章.md', 'type': 'file', 'size': 3, 'revision': 'rev-1'},
        ],
        'replaceFile' => {'success': false, 'currentRevision': 'rev-2'},
        _ => null,
      };
    });
    final access = const LibraryAccess(
      backend: LibraryBackendKind.androidSaf,
      token: 'content://provider/tree/root',
      displayPath: 'root',
      isPending: false,
    );
    final storage = await AndroidSafStorageFactory(
      channel: storageChannel,
    ).open(access);

    final entries = await storage.list(LogicalPath.parse('正文'));
    final result = await storage.replaceFile(
      entries.single.path,
      expectedRevision: 'rev-1',
      bytes: Uint8List.fromList([1, 2, 3]),
    );

    expect(entries.single.revision, 'rev-1');
    expect(result, isA<StorageReplaceConflict>());
    expect(calls.last.arguments, containsPair('path', '正文/第一章.md'));
  });

  test('maps SAF provider failures to application failures', () async {
    messenger.setMockMethodCallHandler(storageChannel, (call) async {
      if (call.method == 'getCapabilities') {
        return {
          'atomicReplace': false,
          'move': true,
          'rename': true,
          'caseSensitive': true,
        };
      }
      throw PlatformException(code: 'already_exists', message: '目标名称已存在。');
    });
    final storage = await AndroidSafStorageFactory(channel: storageChannel)
        .open(
          const LibraryAccess(
            backend: LibraryBackendKind.androidSaf,
            token: 'content://provider/tree/root',
            displayPath: 'root',
            isPending: false,
          ),
        );

    expect(
      () => storage.createDirectory(LogicalPath.parse('重复目录')),
      throwsA(
        isA<LibraryOperationException>().having(
          (error) => error.failure.code,
          'code',
          LibraryFailureCode.alreadyExists,
        ),
      ),
    );
  });
}
