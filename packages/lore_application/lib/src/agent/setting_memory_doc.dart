import 'dart:convert';

/// 设定记忆文档文件名主干；扩展名 `.md` 由存储层自动补全。
///
/// 与章节记忆（`小说记忆.md`）并列，同存小说根目录。主体由模型从章节记忆二次
/// 提炼，按 `## 人物` / `## 地点` / `## 时间线` / `## 伏笔` 四个二级分类组织，
/// 分类下为 `### 名称` 条目 + `- 字段：值` 行。
const String settingMemoryDocName = '设定记忆';

/// 组装设定记忆文档头部：一级标题 + 元数据行（固定生成，不经模型）。
///
/// [now] 仅供测试注入；默认取当前时间。
String formatSettingMemoryHeader({DateTime? now}) {
  final date = _formatDate(now ?? DateTime.now());
  return '# 设定记忆\n> 基于章节记忆生成 · $date';
}

/// 四类设定条目计数（供面板状态展示）。
final class SettingMemoryCounts {
  const SettingMemoryCounts({
    this.characters = 0,
    this.locations = 0,
    this.timeline = 0,
    this.foreshadowing = 0,
  });

  final int characters;
  final int locations;
  final int timeline;
  final int foreshadowing;

  int get total => characters + locations + timeline + foreshadowing;
}

/// 按二级分类统计四类条目数：分类下数 `### ` 条目。
///
/// 分类标题容忍常见别名（如「人物卡」「大事记」）；首个 `##` 之前的内容（文档头）
/// 与未命中任何分类的 `###` 不计入。
SettingMemoryCounts parseSettingMemoryCounts(String text) {
  var section = '';
  var characters = 0;
  var locations = 0;
  var timeline = 0;
  var foreshadowing = 0;
  for (final line in LineSplitter.split(text)) {
    final category = _categoryOf(line);
    if (category != null) {
      section = category;
      continue;
    }
    // 未命中任一分类的二级标题：清空当前分类，其后 `###` 不计入（防误归入上一类）。
    if (RegExp(r'^##(?!#)\s').hasMatch(line)) {
      section = '';
      continue;
    }
    if (!RegExp(r'^###\s').hasMatch(line)) {
      continue;
    }
    switch (section) {
      case '人物':
        characters++;
      case '地点':
        locations++;
      case '时间线':
        timeline++;
      case '伏笔':
        foreshadowing++;
    }
  }
  return SettingMemoryCounts(
    characters: characters,
    locations: locations,
    timeline: timeline,
    foreshadowing: foreshadowing,
  );
}

/// 命中 `## ` 分类标题时返回规范分类名，否则 `null`。容忍常见别名。
String? _categoryOf(String line) {
  const categories = <String, List<String>>{
    '人物': ['人物', '人物卡', '角色'],
    '地点': ['地点', '场景'],
    '时间线': ['时间线', '大事记'],
    '伏笔': ['伏笔'],
  };
  for (final entry in categories.entries) {
    for (final name in entry.value) {
      if (RegExp('^##\\s*$name').hasMatch(line)) {
        return entry.key;
      }
    }
  }
  return null;
}

String _formatDate(DateTime time) {
  final year = time.year.toString().padLeft(4, '0');
  final month = time.month.toString().padLeft(2, '0');
  final day = time.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
