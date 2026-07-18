import 'package:flutter/services.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';

final class AndroidSafStorageFactory implements LibraryStorageFactory {
  AndroidSafStorageFactory({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'dev.lore.app/android_library_storage';

  final MethodChannel _channel;

  @override
  Future<LibraryStorageSession> open(LibraryAccess access) async {
    if (access.backend != LibraryBackendKind.androidSaf) {
      throw ArgumentError.value(access.backend, 'access.backend');
    }
    final raw = await _guardPlatformCall(
      () => _channel.invokeMapMethod<String, Object?>('getCapabilities', {
        'token': access.token,
      }),
    );
    return AndroidSafStorageSession(
      access: access,
      channel: _channel,
      capabilities: StorageCapabilities(
        atomicReplace: raw?['atomicReplace'] == true,
        move: raw?['move'] == true,
        rename: raw?['rename'] == true,
        watch: false,
        caseSensitive: raw?['caseSensitive'] == true,
      ),
    );
  }
}

final class AndroidSafStorageSession implements LibraryStorageSession {
  const AndroidSafStorageSession({
    required this.access,
    required this.channel,
    required this.capabilities,
  });

  final LibraryAccess access;
  final MethodChannel channel;

  @override
  final StorageCapabilities capabilities;

  @override
  Future<List<StorageEntry>> list(LogicalPath directory) async {
    final values = await _guardPlatformCall(
      () => channel.invokeListMethod<Object?>('list', _args(directory)),
    );
    return (values ?? const []).map(_entryFromValue).toList(growable: false);
  }

  @override
  Future<StorageEntry?> stat(LogicalPath path) async {
    final value = await _guardPlatformCall(
      () => channel.invokeMethod<Object?>('stat', _args(path)),
    );
    return value == null ? null : _entryFromValue(value);
  }

  @override
  Future<Uint8List> readBytes(LogicalPath path) async {
    final bytes = await _guardPlatformCall<Uint8List?>(
      () => channel.invokeMethod<Uint8List>('readBytes', _args(path)),
    );
    return bytes ?? Uint8List(0);
  }

  @override
  Future<void> createDirectory(LogicalPath path) {
    return _guardPlatformCall(
      () => channel.invokeMethod<void>('createDirectory', _args(path)),
    );
  }

  @override
  Future<void> createFile(LogicalPath path, Uint8List bytes) {
    return _guardPlatformCall(
      () => channel.invokeMethod<void>('createFile', {
        ..._args(path),
        'bytes': bytes,
      }),
    );
  }

  @override
  Future<StorageReplaceResult> replaceFile(
    LogicalPath path, {
    required String expectedRevision,
    required Uint8List bytes,
  }) async {
    final value = await _guardPlatformCall(
      () => channel.invokeMapMethod<String, Object?>('replaceFile', {
        ..._args(path),
        'expectedRevision': expectedRevision,
        'bytes': bytes,
      }),
    );
    return value?['success'] == true
        ? StorageReplaceSuccess(value?['revision']! as String)
        : StorageReplaceConflict(value?['currentRevision'] as String?);
  }

  @override
  Future<void> move(LogicalPath source, LogicalPath target) {
    return _guardPlatformCall(
      () => channel.invokeMethod<void>('move', {
        'token': access.token,
        'source': source.value,
        'target': target.value,
      }),
    );
  }

  @override
  Future<void> copy(LogicalPath source, LogicalPath target) {
    return _guardPlatformCall(
      () => channel.invokeMethod<void>('copy', {
        'token': access.token,
        'source': source.value,
        'target': target.value,
      }),
    );
  }

  @override
  Future<void> delete(LogicalPath path, {required bool recursive}) {
    return _guardPlatformCall(
      () => channel.invokeMethod<void>('delete', {
        ..._args(path),
        'recursive': recursive,
      }),
    );
  }

  @override
  Stream<StorageChange> watch() => const Stream<StorageChange>.empty();

  Map<String, Object?> _args(LogicalPath path) => {
    'token': access.token,
    'path': path.value,
  };

  StorageEntry _entryFromValue(Object? value) {
    if (value case {
      'path': final String path,
      'type': final String type,
      'size': final int? size,
      'revision': final String? revision,
    }) {
      return StorageEntry(
        path: LogicalPath.parse(path),
        type: type == 'directory'
            ? StorageEntryType.directory
            : StorageEntryType.file,
        size: size,
        revision: revision,
      );
    }
    throw const FormatException('Invalid SAF storage entry.');
  }
}

Future<T> _guardPlatformCall<T>(Future<T> Function() operation) async {
  try {
    return await operation();
  } on PlatformException catch (error) {
    throw LibraryOperationException(
      LibraryFailure(
        code: switch (error.code) {
          'access_denied' => LibraryFailureCode.permissionDenied,
          'not_found' => LibraryFailureCode.notFound,
          'not_writable' => LibraryFailureCode.notWritable,
          'invalid_location' => LibraryFailureCode.invalidLocation,
          'already_exists' => LibraryFailureCode.alreadyExists,
          _ => LibraryFailureCode.io,
        },
        message: error.message ?? 'Android 文件操作失败。',
      ),
    );
  } on MissingPluginException {
    throw const LibraryOperationException(
      LibraryFailure(
        code: LibraryFailureCode.platformUnsupported,
        message: '当前 Android 环境未注册 SAF 存储适配器。',
      ),
    );
  }
}
