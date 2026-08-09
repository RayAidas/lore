import '../library/library_access.dart';
import '../library/library_failure.dart';

abstract interface class LibraryAccessGateway {
  Future<LibraryAccess?> restore();

  Future<LibraryAccess?> select();

  /// 创建名为 [name] 的空目录并作为待确认的书库目录返回；
  /// 用户取消时返回 null。
  Future<LibraryAccess?> create({required String name});

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
