import 'dart:convert';

/// 解析 AI 大纲生成的 Markdown 输出。
///
/// 第 1 步输出约定为 `# 世界观` 与 `# 人物设定` 两个一级章节。这里按一级标题
/// 切分并识别别名；未命中的分类返回 null。若两个标题都未命中，把全文作为世界观
/// 兜底返回，确保内容不丢失。
final class GeneratedOutlineParser {
  const GeneratedOutlineParser();

  static const _worldHeadingAliases = ['世界观', '世界背景', '世界设定'];
  static const _characterHeadingAliases = ['人物设定', '人物', '角色设定'];

  /// 第 1 步（世界观 + 人物设定）输出的切分结果。
  ///
  /// [world] 与 [characters] 为各节正文（不含一级标题），对应标题未找到时为 null。
  ({String? world, String? characters}) splitStepOne(String text) {
    final sections = _splitTopLevel(text);
    final world = _findSection(sections, _worldHeadingAliases);
    final characters = _findSection(sections, _characterHeadingAliases);
    if (world == null && characters == null && text.trim().isNotEmpty) {
      // 兜底：标题未命中，把全文作为世界观保存，避免内容丢失。
      return (world: text.trim(), characters: null);
    }
    return (world: world, characters: characters);
  }

  /// 按一级 Markdown 标题把正文切成 [（标题, 正文）] 段。
  List<({String heading, String body})> _splitTopLevel(String text) {
    final sections = <({String heading, String body})>[];
    String? currentHeading;
    final buffer = <String>[];

    void flush() {
      final heading = currentHeading;
      if (heading != null) {
        sections.add((heading: heading, body: buffer.join('\n').trim()));
        buffer.clear();
      }
    }

    for (final line in LineSplitter.split(text)) {
      if (_isTopLevelHeading(line)) {
        flush();
        currentHeading = line.trim();
      } else {
        buffer.add(line);
      }
    }
    flush();
    return sections;
  }

  /// 匹配首个标题命中别名的节，返回其正文；未命中返回 null。
  String? _findSection(
    List<({String heading, String body})> sections,
    List<String> aliases,
  ) {
    for (final section in sections) {
      final normalized = section.heading
          .replaceFirst(RegExp(r'^#+'), '')
          .trim();
      for (final alias in aliases) {
        if (normalized == alias || normalized.startsWith(alias)) {
          return section.body;
        }
      }
    }
    return null;
  }

  /// 一级标题：单个 `#` 后跟空格（`##` 及以上不算）。
  bool _isTopLevelHeading(String line) => RegExp(r'^#(?!#)\s').hasMatch(line);
}
