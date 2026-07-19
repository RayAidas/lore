import 'package:flutter/services.dart';
import 'package:lore_application/lore_application.dart';

/// macOS reveal 适配：复用 [MacOsLibraryFileOperationsGateway] 的同一条
/// MethodChannel，在 Finder 中选中并定位书库条目。
final class MacOsLibraryRevealGateway implements LibraryRevealGateway {
  MacOsLibraryRevealGateway({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'dev.lore.app/library_access';

  final MethodChannel _channel;

  @override
  Future<void> reveal(
    LibraryAccess access, {
    required String relativePath,
  }) async {
    try {
      await _channel.invokeMethod<void>('revealLibraryEntry', {
        'relativePath': relativePath,
      });
    } on PlatformException catch (error) {
      throw LibraryOperationException(
        LibraryFailure(
          code: switch (error.code) {
            'not_found' => LibraryFailureCode.notFound,
            'invalid_location' => LibraryFailureCode.invalidLocation,
            _ => LibraryFailureCode.io,
          },
          message: error.message ?? '在 Finder 中显示失败。',
        ),
      );
    } on MissingPluginException {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.platformUnsupported,
          message: '当前平台不支持在文件管理器中显示。',
        ),
      );
    }
  }
}
