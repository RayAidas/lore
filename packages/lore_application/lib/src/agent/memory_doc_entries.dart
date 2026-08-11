/// 章节记忆文档的逐章条目模型与合并逻辑。
///
/// `小说记忆.md` 的主体由一系列 `## ` 二级标题条目组成（头部 `# 章节记忆` 与
/// 元数据行由 [MemoryGenerationService] 固定生成，不经模型）。每个条目对应一章，
/// 标题即锚点。为让「增量更新 / 指定章节更新」能稳定定位并替换某个章节的条目，
/// 锚点统一由章节元数据构造的**规范标题**（见 [memoryKeyForNode] 与
/// [canonicalHeadingFor]），而非模型输出的标题或文件名——把编号漂移、模型改写、
/// 序章无编号三类不确定全部归零。
library;

import 'dart:convert';

import 'package:lore_domain/lore_domain.dart';

import 'chapter_memory_doc.dart';

/// 条目的可比较锚点。
sealed class MemoryKey {
  const MemoryKey();
}

/// 编号章节锚点：第 [number] 章。[volume] 仅 perVolume 模式存在——卷内章节为
/// 卷号，正文根级或卷号缺失（目录名如 `第一卷`）为 null（标题写作「未分卷」）。
final class MemoryKeyNumbered extends MemoryKey {
  const MemoryKeyNumbered({this.volume, required this.number});

  final int? volume;
  final int number;

  @override
  bool operator ==(Object other) =>
      other is MemoryKeyNumbered &&
      other.volume == volume &&
      other.number == number;

  @override
  int get hashCode => Object.hash(volume, number);

  @override
  String toString() => volume == null ? '第$number章' : '第$volume卷 第$number章';
}

/// 无编号章节（序章/后记/番外）锚点：文件名主干。用 stem 而非角色词，因为多个
/// 番外（`番外一`/`番外二`）同属 [ContentRole.extra]，角色词不唯一。
final class MemoryKeyRole extends MemoryKey {
  const MemoryKeyRole(this.stem);

  final String stem;

  @override
  bool operator ==(Object other) =>
      other is MemoryKeyRole && other.stem == stem;

  @override
  int get hashCode => stem.hashCode;

  @override
  String toString() => stem;
}

/// 记忆文档中的一个 `## ` 条目。
final class MemoryEntry {
  const MemoryEntry({
    required this.heading,
    required this.body,
    this.key,
    required this.raw,
  });

  /// 标题（不含 `## ` 前缀），如 `第3章 觉醒`。
  final String heading;

  /// 正文（去首尾空白）。
  final String body;

  /// 解析出的锚点；null 表示无法识别为章节条目（不透明条目，合并时原样保留）。
  final MemoryKey? key;

  /// 该节的原始文本（标题行 + 正文，去首尾空行）。未命中目标的不透明条目以此
  /// 原样回写，保证用户手改内容不被规整丢失。
  final String raw;
}

/// 按 `## ` 二级标题把记忆文档切分成条目；首个 `## ` 之前的内容（文档头）忽略。
List<MemoryEntry> parseMemoryEntries(String docText) {
  final lines = LineSplitter.split(docText).toList();
  final entries = <MemoryEntry>[];
  var sectionStart = -1;
  for (var i = 0; i < lines.length; i++) {
    if (_isEntryHeading(lines[i])) {
      if (sectionStart >= 0) {
        entries.add(_section(lines, sectionStart, i));
      }
      sectionStart = i;
    }
  }
  if (sectionStart >= 0) {
    entries.add(_section(lines, sectionStart, lines.length));
  }
  return entries;
}

/// 文档条目是否存在重复锚点（任意 key ≥2）。存在则说明文档无法按 key 唯一寻址
/// （perVolume 旧格式两条 `第1章` 并列，或用户手改产生重复），更新时应整篇重建
/// 而非增量，避免追加出重复摘要。
bool hasDuplicateKeys(List<MemoryEntry> entries) {
  final seen = <MemoryKey>{};
  for (final entry in entries) {
    final key = entry.key;
    if (key == null) {
      continue;
    }
    if (!seen.add(key)) {
      return true;
    }
  }
  return false;
}

/// 由章节节点纯元数据（不读文件）计算锚点。
MemoryKey memoryKeyForNode({
  required ContentNode node,
  required NumberingMode mode,
  required ContentTree tree,
}) {
  final number = node.number;
  if (number != null) {
    if (mode != NumberingMode.perVolume) {
      return MemoryKeyNumbered(number: number);
    }
    return MemoryKeyNumbered(
      volume: _volumeNumber(node, tree),
      number: number,
    );
  }
  return MemoryKeyRole(_fileNameStem(node.relativePath));
}

/// 由章节节点构造规范标题（文档条目锚点 + 展示标题）。[subtitle] 来自章节文件
/// 首行副标题（[ChapterTitleText.tryParse]）；无编号章节仅返回文件名主干。
String canonicalHeadingFor({
  required ContentNode node,
  required NumberingMode mode,
  required ContentTree tree,
  required String subtitle,
}) {
  final number = node.number;
  if (number != null) {
    final trimmed = subtitle.trim();
    final title = trimmed.isEmpty ? '第$number章' : '第$number章 $trimmed';
    if (mode != NumberingMode.perVolume) {
      return title;
    }
    final volume = _volumeNumber(node, tree);
    return volume == null ? '未分卷 $title' : '第$volume卷 $title';
  }
  return _fileNameStem(node.relativePath);
}

/// 把 [updates]（目标章节新条目）合并进 [existing]：命中锚点的原位替换、未命中
/// 的追加末尾、非目标条目原样保留。
List<MemoryEntry> mergeEntries({
  required List<MemoryEntry> existing,
  required List<MemoryEntry> updates,
}) {
  final result = <MemoryEntry>[];
  final remaining = [...updates];
  for (final entry in existing) {
    final key = entry.key;
    final matchIndex = key == null
        ? -1
        : remaining.indexWhere((update) => update.key == key);
    if (matchIndex >= 0) {
      result.add(remaining.removeAt(matchIndex));
    } else {
      result.add(entry);
    }
  }
  result.addAll(remaining);
  return result;
}

/// 组装记忆文档全文：固定头部 + 条目（相邻条目以空行分隔）。
String formatMemoryDoc(
  List<MemoryEntry> entries, {
  required int chapterCount,
  DateTime? now,
}) {
  if (entries.isEmpty) {
    return formatMemoryHeader(chapterCount, now: now);
  }
  final sections = entries.map((entry) => entry.raw.trim()).join('\n\n');
  return '${formatMemoryHeader(chapterCount, now: now)}\n\n$sections';
}

/// 章节所在卷号；父节点非卷或卷号缺失（目录名如 `第一卷`，`_volumeNumber` 只认
/// `第(\d+)卷`）时返回 null（按「未分卷」处理）。
int? _volumeNumber(ContentNode node, ContentTree tree) {
  final parent = tree.nodeById(node.parentId);
  if (parent == null || parent.type != ContentNodeType.volume) {
    return null;
  }
  return parent.number;
}

/// 文件主干名（basename 去扩展名），如 `正文/序章.md` → `序章`。
String _fileNameStem(String relativePath) {
  final slash = relativePath.lastIndexOf('/');
  final name = slash < 0 ? relativePath : relativePath.substring(slash + 1);
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? name : name.substring(0, dot);
}

/// 二级标题行：`## ` 后跟空白（拒绝 `###` 与 `##标题` 无空格）。
bool _isEntryHeading(String line) => RegExp(r'^##(?!#)\s').hasMatch(line);

/// 由行区间构造条目：首行为标题（剥 `## ` 前缀），其余为正文；`raw` 保留原始
/// 文本供未命中条目原样回写。
MemoryEntry _section(List<String> lines, int start, int end) {
  final heading = lines[start].substring(3).trim();
  final bodyLines = <String>[];
  for (var i = start + 1; i < end; i++) {
    bodyLines.add(lines[i]);
  }
  final raw = lines.sublist(start, end).join('\n').trim();
  return MemoryEntry(
    heading: heading,
    body: bodyLines.join('\n').trim(),
    key: _keyOfHeading(heading),
    raw: raw,
  );
}

/// 由标题行解析锚点；无法识别为章节条目时返回 null。
MemoryKey? _keyOfHeading(String heading) {
  final volumeChapter = RegExp(r'^第(\d+)卷\s+第(\d+)章').firstMatch(heading);
  if (volumeChapter != null) {
    return MemoryKeyNumbered(
      volume: int.tryParse(volumeChapter.group(1)!),
      number: int.parse(volumeChapter.group(2)!),
    );
  }
  final chapter = RegExp(r'^第(\d+)章').firstMatch(heading);
  if (chapter != null) {
    return MemoryKeyNumbered(number: int.parse(chapter.group(1)!));
  }
  final unvolumed = RegExp(r'^未分卷\s+第(\d+)章').firstMatch(heading);
  if (unvolumed != null) {
    return MemoryKeyNumbered(number: int.parse(unvolumed.group(1)!));
  }
  // `\w` 不含汉字，`\b` 词边界对 CJK 标题不成立，改用「后跟空白或结尾」。
  if (RegExp(r'^序章(?=\s|$)').hasMatch(heading)) {
    return const MemoryKeyRole('序章');
  }
  if (RegExp(r'^后记(?=\s|$)').hasMatch(heading)) {
    return const MemoryKeyRole('后记');
  }
  final extra = RegExp(r'^番外(\S*)').firstMatch(heading);
  if (extra != null) {
    return MemoryKeyRole('番外${extra.group(1) ?? ''}');
  }
  return null;
}
