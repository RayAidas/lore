import 'package:lore_domain/lore_domain.dart';

import '../library/library_access.dart';
import '../library/deletion.dart';
import '../library/novel_structure.dart';

abstract interface class ContentTreeRepository {
  Future<NovelStructureMutation> createVolume(
    LibraryAccess access, {
    required NovelId novelId,
  });

  Future<NovelStructureMutation> createChapter(
    LibraryAccess access, {
    required NovelId novelId,
    ContentId? volumeId,
  });

  Future<NovelStructureMutation> renameNode(
    LibraryAccess access, {
    required NovelId novelId,
    required ContentId nodeId,
    required String newName,
  });

  Future<NovelStructureMutation> moveChapter(
    LibraryAccess access, {
    required NovelId novelId,
    required ContentId chapterId,
    ContentId? volumeId,
  });

  Future<NovelStructureMutation> reorderNode(
    LibraryAccess access, {
    required NovelId novelId,
    required ContentId nodeId,
    required int newIndex,
  });

  /// 批量更新章节正文字数并写回 content.json（revision 自增）。仅更新
  /// [characterCounts] 中出现的章节节点；其余节点不变。返回更新后的快照，
  /// `entry` 为 `null`（字数更新不改选中）。
  Future<NovelStructureMutation> updateChapterCharacterCounts(
    LibraryAccess access, {
    required NovelId novelId,
    required Map<ContentId, int> characterCounts,
  });

  Future<DeletionResult> deleteNode(
    LibraryAccess access, {
    required NovelId novelId,
    required ContentId nodeId,
  });

  Future<NovelReconciliationResult> reconcile(
    LibraryAccess access, {
    required NovelId novelId,
  });
}
