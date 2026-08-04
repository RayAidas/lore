import 'dart:convert';

import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 基于 [SharedPreferences] 的大纲关联持久化适配器。
///
/// 单一 JSON 字符串 key（`lore.agent.linked_outlines`），结构
/// `{schemaVersion:1, byNovelId:{<novelId>:[<大纲相对路径>]}}`。解析失败或版本
/// 不符时 [load] 返回 `null`，让上层回退为空关联。
final class SharedPreferencesLinkedOutlinesRepository
    implements LinkedOutlinesRepository {
  const SharedPreferencesLinkedOutlinesRepository();

  static const _key = 'lore.agent.linked_outlines';
  static const _schemaVersion = 1;

  @override
  Future<NovelOutlineLinks?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_key);
    if (encoded == null) {
      return null;
    }
    try {
      final value = jsonDecode(encoded);
      if (value is! Map<String, Object?> ||
          value['schemaVersion'] != _schemaVersion) {
        return null;
      }
      final rawByNovel = value['byNovelId'];
      if (rawByNovel is! Map<String, Object?>) {
        return const NovelOutlineLinks.empty();
      }
      final byNovelId = <String, List<String>>{};
      rawByNovel.forEach((novelId, rawPaths) {
        if (rawPaths is List<Object?> && rawPaths.every((e) => e is String)) {
          byNovelId[novelId] = rawPaths.whereType<String>().toList();
        }
      });
      return NovelOutlineLinks(byNovelId);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> save(NovelOutlineLinks links) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _key,
      jsonEncode({
        'schemaVersion': _schemaVersion,
        'byNovelId': links.pathsByNovelId,
      }),
    );
  }
}
