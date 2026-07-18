import 'package:flutter/services.dart';
import 'package:lore_application/lore_application.dart';

/// macOS security-scoped bookmark access adapter.
final class MacOsLibraryAccessGateway implements LibraryAccessGateway {
  MacOsLibraryAccessGateway({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'dev.lore.app/library_access';

  final MethodChannel _channel;

  @override
  Future<LibraryAccess?> restore() {
    return _invokeAccess('restoreLibraryDirectory', isPending: false);
  }

  @override
  Future<LibraryAccess?> select() {
    return _invokeAccess('selectLibraryDirectory', isPending: true);
  }

  @override
  Future<void> commit() => _invokeVoid('commitLibraryDirectory');

  @override
  Future<void> discard() => _invokeVoid('discardLibraryDirectorySelection');

  @override
  Future<void> clear() => _invokeVoid('clearLibraryDirectory');

  Future<LibraryAccess?> _invokeAccess(
    String method, {
    required bool isPending,
  }) async {
    try {
      final value = await _channel.invokeMethod<Object?>(method);
      if (value == null) {
        return null;
      }
      if (value case {
        'token': final String token,
        'displayPath': final String displayPath,
      }) {
        return LibraryAccess(
          token: token,
          displayPath: displayPath,
          isPending: isPending,
        );
      }
      throw const LibraryAccessException(
        LibraryFailure(
          code: LibraryFailureCode.io,
          message: '系统返回了无法识别的书库目录信息。',
        ),
      );
    } on PlatformException catch (error) {
      throw LibraryAccessException(_mapPlatformFailure(error));
    } on MissingPluginException {
      throw const LibraryAccessException(
        LibraryFailure(
          code: LibraryFailureCode.platformUnsupported,
          message: '当前平台尚未支持书库目录授权。',
        ),
      );
    }
  }

  Future<void> _invokeVoid(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on PlatformException catch (error) {
      throw LibraryAccessException(_mapPlatformFailure(error));
    } on MissingPluginException {
      throw const LibraryAccessException(
        LibraryFailure(
          code: LibraryFailureCode.platformUnsupported,
          message: '当前平台尚未支持书库目录授权。',
        ),
      );
    }
  }

  LibraryFailure _mapPlatformFailure(PlatformException error) {
    final code = switch (error.code) {
      'access_denied' => LibraryFailureCode.permissionDenied,
      'bookmark_unavailable' => LibraryFailureCode.permissionDenied,
      'bookmark_resolution_failed' => LibraryFailureCode.permissionDenied,
      'invalid_location' => LibraryFailureCode.invalidLocation,
      'platform_unsupported' => LibraryFailureCode.platformUnsupported,
      _ => LibraryFailureCode.io,
    };
    return LibraryFailure(code: code, message: error.message ?? '无法访问书库目录。');
  }
}
