import 'package:lore_domain/lore_domain.dart';

import '../library/deletion.dart';
import '../library/library_access.dart';
import '../library/novel_structure.dart';

abstract interface class NovelRepository {
  Future<List<NovelSnapshot>> listNovels(LibraryAccess access);

  Future<NovelSnapshot> loadNovel(
    LibraryAccess access, {
    required NovelId novelId,
  });

  Future<NovelStructureMutation> createNovel(
    LibraryAccess access, {
    required String title,
    ChapterFormat chapterFormat = ChapterFormat.markdown,
  });

  /// 由已解析的章节列表一次性创建小说（建目录、写各章文件、生成 content.json、
  /// 注册），用于 TXT 导入。章节数据来自纯 domain 的 [TxtNovelParser]。
  /// 书名重复时抛 `LibraryFailureCode.alreadyExists`，由调用方负责重命名循环。
  Future<NovelStructureMutation> importNovel(
    LibraryAccess access, {
    required String title,
    required List<NovelChapterImport> chapters,
    ChapterFormat chapterFormat = ChapterFormat.text,
  });

  Future<NovelStructureMutation> registerExistingNovel(
    LibraryAccess access, {
    required String relativePath,
  });

  Future<NovelStructureMutation> renameNovel(
    LibraryAccess access, {
    required NovelId novelId,
    required String newName,
  });

  Future<NovelStructureMutation> renameBody(
    LibraryAccess access, {
    required NovelId novelId,
    required String newName,
  });

  Future<DeletionResult> deleteNovel(
    LibraryAccess access, {
    required NovelId novelId,
  });
}
