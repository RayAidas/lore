/// AI 生成大纲的输入：用户在面板中按提示填写的主题与各类设定要求。
///
/// 各设定字段均可为空字符串，由用户在面板中自由填写；`theme`（主题/书名）
/// 为必填，同时用作生成文件的命名主干。
final class OutlineGenerationRequest {
  const OutlineGenerationRequest({
    required this.theme,
    this.worldSetting = '',
    this.characterSetting = '',
    this.volumeSetting = '',
    this.chapterSetting = '',
    this.extraPrompt = '',
  });

  /// 主题/书名（必填，用作输出文件命名主干）。
  final String theme;

  /// 世界背景要求：时代、地理、力量体系、势力等。
  final String worldSetting;

  /// 人物设定要求：主角、配角、反派等。
  final String characterSetting;

  /// 卷设定：卷数、各卷名称等。
  final String volumeSetting;

  /// 章设定：每卷章数、章节粒度等。
  final String chapterSetting;

  /// 补充要求：任意额外的创作约束或提示。
  final String extraPrompt;

  OutlineGenerationRequest copyWith({
    String? theme,
    String? worldSetting,
    String? characterSetting,
    String? volumeSetting,
    String? chapterSetting,
    String? extraPrompt,
  }) {
    return OutlineGenerationRequest(
      theme: theme ?? this.theme,
      worldSetting: worldSetting ?? this.worldSetting,
      characterSetting: characterSetting ?? this.characterSetting,
      volumeSetting: volumeSetting ?? this.volumeSetting,
      chapterSetting: chapterSetting ?? this.chapterSetting,
      extraPrompt: extraPrompt ?? this.extraPrompt,
    );
  }
}
