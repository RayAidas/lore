/// 导出章节（标题 + 正文），由 UI 层从已读章节文件拼装后交给合成器。
final class ExportChapter {
  const ExportChapter({required this.title, required this.body});

  final String title;
  final String body;
}

/// TXT 导出格式选项。
final class TxtExportOptions {
  const TxtExportOptions({
    this.includeTitles = true,
    this.blankLineBetween = true,
  });

  /// 是否在每章正文前输出章节标题行。
  final bool includeTitles;

  /// 章与章之间是否留空行分隔（关闭时章节直接相邻）。
  final bool blankLineBetween;
}

/// 把多章合并成单个 TXT 字符串的纯逻辑工具。
///
/// 每章组成一个块：`includeTitles` 且标题非空时为「标题 + 空行 + 正文」，
/// 否则仅正文（去首尾空白，空章节跳过）。块之间按 [TxtExportOptions.blankLineBetween]
/// 用空行或单换行连接，结果末尾补一个换行以符合文本文件惯例。
abstract final class TxtExportComposer {
  const TxtExportComposer._();

  static String compose({
    required List<ExportChapter> chapters,
    required TxtExportOptions options,
  }) {
    final chunks = <String>[];
    for (final chapter in chapters) {
      final title = chapter.title.trim();
      final body = chapter.body.trim();
      if (options.includeTitles && title.isNotEmpty) {
        chunks.add(body.isEmpty ? title : '$title\n\n$body');
      } else if (body.isNotEmpty) {
        chunks.add(body);
      }
    }
    if (chunks.isEmpty) {
      return '';
    }
    final joined = chunks.join(options.blankLineBetween ? '\n\n' : '\n');
    return '$joined\n';
  }
}
