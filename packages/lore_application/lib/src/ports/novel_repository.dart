import 'package:lore_domain/lore_domain.dart';

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
}
