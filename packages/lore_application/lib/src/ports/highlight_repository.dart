import 'package:lore_domain/lore_domain.dart';

import '../library/library_access.dart';

/// 文字高亮的持久化端口。
///
/// 高亮按小说聚合落盘到 `<novel>/.lore/highlights.json`,内部以文档
/// relativePath([documentId])为键索引。一个文档的高亮集 [HighlightCollection]
/// 含其 documentRevision 与段落指纹序列,供外部修改后做复原对齐。
abstract interface class HighlightRepository {
  Future<HighlightCollection?> loadHighlights(
    LibraryAccess access, {
    required NovelId novelId,
    required String documentId,
  });

  Future<void> saveHighlights(
    LibraryAccess access, {
    required NovelId novelId,
    required String documentId,
    required HighlightCollection collection,
  });

  Future<void> deleteHighlights(
    LibraryAccess access, {
    required NovelId novelId,
    required String documentId,
  });
}
