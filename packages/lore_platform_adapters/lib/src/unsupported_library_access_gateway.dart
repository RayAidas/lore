import 'package:lore_application/lore_application.dart';

/// Fallback used by platforms without a registered library adapter.
final class UnsupportedLibraryAccessGateway implements LibraryAccessGateway {
  const UnsupportedLibraryAccessGateway();

  LibraryAccessException get _error => const LibraryAccessException(
    LibraryFailure(
      code: LibraryFailureCode.platformUnsupported,
      message: 'Android 书库支持将在后续版本提供。',
    ),
  );

  @override
  Future<void> clear() => Future<void>.error(_error);

  @override
  Future<void> commit() => Future<void>.error(_error);

  @override
  Future<void> discard() => Future<void>.error(_error);

  @override
  Future<LibraryAccess?> restore() => Future<LibraryAccess?>.error(_error);

  @override
  Future<LibraryAccess?> select() => Future<LibraryAccess?>.error(_error);
}
