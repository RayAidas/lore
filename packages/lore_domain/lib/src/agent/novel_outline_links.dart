/// 每部小说关联的大纲文件路径集合。
///
/// 键为小说 id（`NovelId.value`），值为该小说下已关联大纲文件的书库相对路径
/// （可直接用于 `readDocument`）。关联选择按小说持久化（SharedPreferences），
/// 换小说各记各的。
final class NovelOutlineLinks {
  const NovelOutlineLinks(this.pathsByNovelId);

  const NovelOutlineLinks.empty() : pathsByNovelId = const {};

  final Map<String, List<String>> pathsByNovelId;

  /// 某部小说已关联的大纲路径（无则空列表）。
  List<String> forNovel(String novelId) =>
      List.unmodifiable(pathsByNovelId[novelId] ?? const <String>[]);

  /// 关联一个大纲（幂等：已存在不重复添加）。
  NovelOutlineLinks withLink(String novelId, String path) {
    final existing = pathsByNovelId[novelId] ?? const <String>[];
    if (existing.contains(path)) {
      return this;
    }
    final next = <String, List<String>>{...pathsByNovelId};
    next[novelId] = [...existing, path];
    return NovelOutlineLinks(next);
  }

  /// 取消关联一个大纲；该小说关联清空后移除对应键。
  NovelOutlineLinks withoutLink(String novelId, String path) {
    final existing = pathsByNovelId[novelId] ?? const <String>[];
    if (!existing.contains(path)) {
      return this;
    }
    final remaining = existing.where((item) => item != path).toList();
    final next = <String, List<String>>{...pathsByNovelId};
    if (remaining.isEmpty) {
      next.remove(novelId);
    } else {
      next[novelId] = remaining;
    }
    return NovelOutlineLinks(next);
  }
}
