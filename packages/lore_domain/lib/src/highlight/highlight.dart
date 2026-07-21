/// 文字高亮领域模型。
///
/// 高亮是附着在文档 `[start, end)` 字符区间上的批注。核心设计约束:
///
/// - **颜色定格**:[colorArgb] 是创建时拍定的 ARGB 值,用户后续修改调色板
///   不会回溯改变已有高亮颜色(批注是历史记录)。
/// - **位置可维护**:[start]/[end] 是文档全局字符 offset。本应用编辑时由
///   [shiftHighlights] 精确维护;外部修改文档后由 [reconcileHighlights] 基于
///   [anchorText] 与段落指纹重定位。
/// - **锚点快照**:[anchorText] 是 [start, end) 覆盖的原文快照,反映"上次持久化
///   时"的内容。它在 [shiftHighlights] 中不变(只在持久化时由调用方用
///   `text.substring(start, end)` 刷新),这样下次读盘若文档已被外部修改,
///   才能与当前段落文本对比出漂移。
final class Highlight {
  const Highlight({
    required this.id,
    required this.start,
    required this.end,
    required this.colorArgb,
    required this.anchorText,
  });

  /// 稳定标识(跨编辑/持久化保持,用于追踪同一条高亮)。
  final String id;

  /// 起始字符 offset(含),基于归一化后的文档文本(`\n` 分隔,无 BOM/`\r`)。
  final int start;

  /// 结束字符 offset(不含)。
  final int end;

  /// ARGB 颜色值(`0xAARRGGBB`)。
  final int colorArgb;

  /// `[start, end)` 原文快照,外部修改后段内重定位用。
  final String anchorText;

  bool get isCollapsed => start >= end;

  int get length => end - start;

  /// 复制并替换位置/颜色/锚点。**不暴露 id**——身份不可变。
  Highlight copyWith({
    int? start,
    int? end,
    int? colorArgb,
    String? anchorText,
  }) {
    return Highlight(
      id: id,
      start: start ?? this.start,
      end: end ?? this.end,
      colorArgb: colorArgb ?? this.colorArgb,
      anchorText: anchorText ?? this.anchorText,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is Highlight &&
        other.id == id &&
        other.start == start &&
        other.end == end &&
        other.colorArgb == colorArgb &&
        other.anchorText == anchorText;
  }

  @override
  int get hashCode => Object.hash(id, start, end, colorArgb, anchorText);
}

/// 一个文档的全部高亮及其复原元数据。
///
/// 持久化到 `<novel>/.lore/highlights.json`(按文档 relativePath 索引)。
/// 只有"含有高亮"的文档才会落盘该集合;无高亮的文档不产生记录。
final class HighlightCollection {
  const HighlightCollection({
    required this.documentRevision,
    required this.paragraphDigests,
    required this.highlights,
  });

  /// 创建或最后确认该集合时所基于的文档字节级 sha256(与
  /// `DocumentSnapshot.revision.value` 同源)。加载时若与当前文档 revision 一致,
  /// 可直接信任 [highlights] 的 offset,跳过 [reconcileHighlights]。
  final String documentRevision;

  /// 上次确认时的全文段落指纹序列(每段 `"$length:${sha256 前 16 位}"`)。
  /// 与 [highlights] 同源文档,用于段落级 LCS 对齐、追踪段落剪切移动。
  final List<String> paragraphDigests;

  final List<Highlight> highlights;

  /// 空集合(文档尚无高亮,但仍记录 revision 以便后续比对)。
  static HighlightCollection empty(String documentRevision) {
    return HighlightCollection(
      documentRevision: documentRevision,
      paragraphDigests: const [],
      highlights: const [],
    );
  }

  HighlightCollection copyWith({
    String? documentRevision,
    List<String>? paragraphDigests,
    List<Highlight>? highlights,
  }) {
    return HighlightCollection(
      documentRevision: documentRevision ?? this.documentRevision,
      paragraphDigests: paragraphDigests ?? this.paragraphDigests,
      highlights: highlights ?? this.highlights,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is HighlightCollection &&
        other.documentRevision == documentRevision &&
        _listEquals<String>(other.paragraphDigests, paragraphDigests) &&
        _listEquals<Highlight>(other.highlights, highlights);
  }

  @override
  int get hashCode => Object.hash(
        documentRevision,
        Object.hashAll(paragraphDigests),
        Object.hashAll(highlights),
      );
}

/// 高亮调色板默认色。
///
/// 5 个暖色调槽位,契合 Lore 的 sepia 主题。用户可在偏好中替换槽位颜色
/// (`AppPreferences.highlightPalette`);高亮本身存定格的 [Highlight.colorArgb],
/// 改调色板不影响已有高亮。
abstract final class HighlightPalette {
  const HighlightPalette._();

  static const List<int> defaults = <int>[
    0xFFFFD54F, // 黄
    0xFFA5D6A7, // 绿
    0xFF90CAF9, // 蓝
    0xFFF48FB1, // 粉
    0xFFFFAB91, // 橙
  ];
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
