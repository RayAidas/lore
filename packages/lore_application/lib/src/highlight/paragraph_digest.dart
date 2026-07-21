import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:lore_domain/lore_domain.dart';

/// 单段指纹:`"$length:${sha256 前 16 位}"`。长度作一级消歧,降低(罕见)短文本
/// 哈希碰撞。基于**归一化后的文本**(`\n` 分隔,无 BOM/`\r`),与上层 controller
/// 看到的文本一致——故必须用 `DocumentSnapshot.text` 派生,不能重新解码磁盘字节。
String paragraphDigest(String paragraphText) {
  final hash = sha256.convert(utf8.encode(paragraphText)).toString();
  return '${paragraphText.length}:${hash.substring(0, 16)}';
}

/// 文档的段落结构剖面:一次 `split('\n')` 同时产出三视图,供 reconcile 使用。
final class ParagraphProfile {
  const ParagraphProfile({
    required this.texts,
    required this.digests,
    required this.spans,
  });

  /// 各段原文(段内 `indexOf` 重定位用)。
  final List<String> texts;

  /// 各段指纹序列(LCS 对齐用)。
  final List<String> digests;

  /// 各段全局 offset 范围 `[start, end)`(不含段尾换行)。
  final List<ParagraphSpan> spans;

  static const empty = ParagraphProfile(texts: [], digests: [], spans: []);
}

/// 计算文档的段落剖面。空文档返回 [ParagraphProfile.empty]。
ParagraphProfile computeParagraphProfile(String documentText) {
  if (documentText.isEmpty) {
    return ParagraphProfile.empty;
  }
  final paragraphs = documentText.split('\n');
  final digests = <String>[];
  final spans = <ParagraphSpan>[];
  var acc = 0;
  for (final p in paragraphs) {
    digests.add(paragraphDigest(p));
    spans.add(paragraphSpan(acc, acc + p.length));
    acc += p.length + 1; // +1 for '\n'
  }
  return ParagraphProfile(texts: paragraphs, digests: digests, spans: spans);
}

/// 从存储的段落指纹序列(含 length 前缀)重建各段全局 offset 范围。避免持久化
/// 时额外存储 spans——[paragraphDigest] 的 `"$length:..."` 前缀已携带长度,
/// 累加(段间一个 `\n`)即得。损坏的 length 解析为 0,不抛错(best-effort)。
List<ParagraphSpan> paragraphSpansFromDigests(List<String> digests) {
  if (digests.isEmpty) return const [];
  final spans = <ParagraphSpan>[];
  var acc = 0;
  for (final d in digests) {
    final colon = d.indexOf(':');
    final len = colon > 0 ? (int.tryParse(d.substring(0, colon)) ?? 0) : 0;
    spans.add(paragraphSpan(acc, acc + len));
    acc += len + 1; // +1 for '\n'
  }
  return spans;
}
