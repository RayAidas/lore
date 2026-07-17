import '../library/library_access.dart';
import '../library/library_failure.dart';

abstract interface class LibraryAccessGateway {
  Future<LibraryAccess?> restore();

  Future<LibraryAccess?> select();

  Future<void> commit();

  Future<void> discard();

  Future<void> clear();
}

final class LibraryAccessException implements Exception {
  const LibraryAccessException(this.failure);

  final LibraryFailure failure;

  @override
  String toString() => failure.message;
}
