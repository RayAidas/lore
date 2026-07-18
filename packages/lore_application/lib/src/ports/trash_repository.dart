import '../library/library_access.dart';

enum TrashItemType { novel, volume, chapter, entry }

/// 恢复冲突策略。默认 [rename]，追加后缀避免覆盖既有内容。
enum RestoreConflictStrategy { overwrite, skip, rename }

final class TrashItemChild {
  const TrashItemChild({
    required this.nodeId,
    required this.originalRelativePath,
    required this.trashRelativePath,
  });

  final String nodeId;
  final String originalRelativePath;
  final String trashRelativePath;
}

final class TrashItem {
  const TrashItem({
    required this.token,
    required this.type,
    required this.originalRelativePath,
    required this.trashRelativePath,
    required this.deletedAt,
    required this.restorable,
    this.novelId,
    this.nodeId,
    this.novelRootPath,
    this.children = const [],
  });

  final String token;
  final TrashItemType type;
  final String originalRelativePath;
  final String trashRelativePath;
  final DateTime deletedAt;
  final bool restorable;
  final String? novelId;
  final String? nodeId;
  final String? novelRootPath;
  final List<TrashItemChild> children;
}

/// 回收站端口：枚举、恢复、永久删除与清空。
///
/// 恢复（[restore]）会把文件移回原位并在内容树重建节点身份；冲突按
/// [RestoreConflictStrategy] 处理。永久删除（[purge]/[empty]）不可逆，
/// 上层必须二次确认。
abstract interface class TrashRepository {
  Future<List<TrashItem>> listItems(LibraryAccess access);

  Future<TrashItem> restore(
    LibraryAccess access, {
    required String trashToken,
    RestoreConflictStrategy strategy = RestoreConflictStrategy.rename,
  });

  Future<void> purge(LibraryAccess access, {required String trashToken});

  Future<void> empty(LibraryAccess access);
}
