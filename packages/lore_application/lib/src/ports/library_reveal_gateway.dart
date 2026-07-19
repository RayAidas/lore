import '../library/library_access.dart';

/// 在系统文件管理器中显示书库条目（macOS Finder 选中文件/目录）。
///
/// local-first 写作的看家操作：用户常需查看实际文件、拖入素材或备份。
abstract interface class LibraryRevealGateway {
  Future<void> reveal(LibraryAccess access, {required String relativePath});
}
