import 'package:flutter/services.dart';
import 'package:lore_application/lore_application.dart';

final class AndroidSafLibraryAccessGateway implements LibraryAccessGateway {
  AndroidSafLibraryAccessGateway({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'dev.lore.app/android_library_access';

  final MethodChannel _channel;

  @override
  Future<LibraryAccess?> restore() =>
      _invokeAccess('restoreLibraryDirectory', isPending: false);

  @override
  Future<LibraryAccess?> select() =>
      _invokeAccess('selectLibraryDirectory', isPending: true);

  @override
  Future<LibraryAccess?> create({required String name}) => _invokeAccess(
    'createLibraryDirectory',
    isPending: true,
    arguments: {'name': name},
  );

  @override
  Future<void> commit() => _invokeVoid('commitLibraryDirectory');

  @override
  Future<void> discard() => _invokeVoid('discardLibraryDirectorySelection');

  @override
  Future<void> clear() => _invokeVoid('clearLibraryDirectory');

  Future<LibraryAccess?> _invokeAccess(
    String method, {
    required bool isPending,
    Map<String, Object?>? arguments,
  }) async {
    try {
      final value = await _channel.invokeMethod<Object?>(method, arguments);
      if (value == null) {
        return null;
      }
      if (value case {
        'token': final String token,
        'displayPath': final String displayPath,
      }) {
        return LibraryAccess(
          backend: LibraryBackendKind.androidSaf,
          token: token,
          displayPath: displayPath,
          isPending: isPending,
        );
      }
      throw const LibraryAccessException(
        LibraryFailure(
          code: LibraryFailureCode.io,
          message: '系统返回了无法识别的 Android 书库信息。',
        ),
      );
    } on PlatformException catch (error) {
      throw LibraryAccessException(_failure(error));
    } on MissingPluginException {
      throw const LibraryAccessException(
        LibraryFailure(
          code: LibraryFailureCode.platformUnsupported,
          message: '当前 Android 环境未注册 SAF 适配器。',
        ),
      );
    }
  }

  Future<void> _invokeVoid(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on PlatformException catch (error) {
      throw LibraryAccessException(_failure(error));
    }
  }

  LibraryFailure _failure(PlatformException error) {
    return LibraryFailure(
      code: switch (error.code) {
        'access_denied' => LibraryFailureCode.permissionDenied,
        'invalid_location' => LibraryFailureCode.invalidLocation,
        'invalid_name' => LibraryFailureCode.invalidName,
        'already_exists' => LibraryFailureCode.alreadyExists,
        'not_found' => LibraryFailureCode.notFound,
        'not_writable' => LibraryFailureCode.notWritable,
        _ => LibraryFailureCode.io,
      },
      message: error.message ?? '无法访问 Android 书库目录。',
    );
  }
}
