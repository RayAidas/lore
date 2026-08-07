/// AI 分步生成的大纲结果，按分类拆分后待保存到小说的对应目录：
///
/// - [worldSection] → `世界观/<主干>-世界观.md`
/// - [characterSection] → `人物/<主干>-人物.md`
/// - [chaptersSection] → `大纲/<主干>.md`
///
/// 世界与人物为空表示该分类未生成（或解析未命中），保存时跳过对应文件。
final class GeneratedOutline {
  const GeneratedOutline({
    required this.worldSection,
    required this.characterSection,
    required this.chaptersSection,
  });

  /// 世界观 Markdown 正文（不含 `# 世界观` 一级标题）。
  final String worldSection;

  /// 人物设定 Markdown 正文（不含 `# 人物设定` 一级标题）。
  final String characterSection;

  /// 卷章大纲完整 Markdown（含 `# 卷章大纲` 及以下卷/章标题）。
  final String chaptersSection;

  GeneratedOutline copyWith({
    String? worldSection,
    String? characterSection,
    String? chaptersSection,
  }) {
    return GeneratedOutline(
      worldSection: worldSection ?? this.worldSection,
      characterSection: characterSection ?? this.characterSection,
      chaptersSection: chaptersSection ?? this.chaptersSection,
    );
  }
}
