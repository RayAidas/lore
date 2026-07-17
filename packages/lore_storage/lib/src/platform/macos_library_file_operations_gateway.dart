import 'package:flutter/services.dart';
import 'package:lore_application/lore_application.dart';

final class MacOsLibraryFileOperationsGateway
    implements LibraryFileOperationsGateway {
  MacOsLibraryFileOperationsGateway({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'dev.lore.app/library_access';

  final MethodChannel _channel;

  @override
  Future<void> rename(
    LibraryAccess access, {
    required String sourcePath,
    required String targetPath,
  }) async {
    try {
      await _channel.invokeMethod<void>('renameLibraryEntry', {
        'sourcePath': sourcePath,
        'targetPath': targetPath,
      });
    } on PlatformException catch (error) {
      throw LibraryOperationException(
        LibraryFailure(
          code: switch (error.code) {
            'name_conflict' => LibraryFailureCode.alreadyExists,
            'not_found' => LibraryFailureCode.notFound,
            'invalid_location' => LibraryFailureCode.invalidLocation,
            'access_denied' => LibraryFailureCode.notWritable,
            _ => LibraryFailureCode.io,
          },
          message: error.message ?? '重命名失败。',
        ),
      );
    } on MissingPluginException {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.platformUnsupported,
          message: '当前平台不支持安全重命名。',
        ),
      );
    }
  }

  @override
  Future<bool> replaceDocument(
    LibraryAccess access, {
    required String relativePath,
    required String expectedRevision,
    required Uint8List bytes,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('replaceLibraryDocument', {
            'relativePath': relativePath,
            'expectedRevision': expectedRevision,
            'bytes': bytes,
          }) ??
          false;
    } on PlatformException catch (error) {
      throw LibraryOperationException(
        LibraryFailure(
          code: switch (error.code) {
            'not_found' => LibraryFailureCode.notFound,
            'invalid_location' => LibraryFailureCode.invalidLocation,
            'access_denied' => LibraryFailureCode.notWritable,
            _ => LibraryFailureCode.io,
          },
          message: error.message ?? '文档保存失败。',
        ),
      );
    } on MissingPluginException {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.platformUnsupported,
          message: '当前平台不支持安全文档保存。',
        ),
      );
    }
  }
}
