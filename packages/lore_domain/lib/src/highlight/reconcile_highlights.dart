import 'dart:math' as math;

import 'highlight.dart';

/// 段落的全局字符范围 `[start, end)`(不含段尾换行符)。
typedef ParagraphSpan = ({int start, int end});

ParagraphSpan paragraphSpan(int start, int end) => (start: start, end: end);

/// 复原结果:[located] 为成功重定位的高亮(新坐标、刷新的 anchorText),
/// [lost] 为无法重定位的(段被删、锚点失配、跨段)。
final class ReconcileResult {
  const ReconcileResult({required this.located, required this.lost});

  final List<Highlight> located;
  final List<Highlight> lost;

  static const empty = ReconcileResult(located: [], lost: []);
}

/// 段落对齐:返回 `oldParaIdx → newParaIdx?`(null 表示该旧段在新文档中无对应,
/// 即被删除)。
///
/// 三层策略,逐层放宽:
///
/// 1. **LCS 精确匹配**:在 digest 序列上求最长公共子序列,保序匹配 digest 完全
///    相同的段。这是最可信的:段未变,offset 可直接信任。
/// 2. **相同 digest 候选消歧**:LCS 因保序约束漏配的段(典型场景:整段被剪切
///    挪到别处),若其 digest 在新序列中存在且未被占用,按"邻居一致性"打分取
///    最高;无邻居支持时也接受候选(选错位置的代价 < 丢失整段高亮)。
/// 3. **同位置兜底**:仍未匹配的段(典型场景:段内文字被修改、digest 变了但
///    段仍在原位),若原位置在新序列范围内且未占用,对齐到同位置,后续由
///    [reconcileHighlights] 用 anchorText 段内重定位。
Map<int, int?> alignParagraphs(
  List<String> oldDigests,
  List<String> newDigests,
) {
  final m = oldDigests.length;
  final n = newDigests.length;
  if (m == 0 || n == 0) {
    return {for (var i = 0; i < m; i++) i: null};
  }

  // --- 第 1 层:LCS ---
  final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));
  for (var i = m - 1; i >= 0; i--) {
    for (var j = n - 1; j >= 0; j--) {
      dp[i][j] = oldDigests[i] == newDigests[j]
          ? dp[i + 1][j + 1] + 1
          : math.max(dp[i + 1][j], dp[i][j + 1]);
    }
  }
  final aligned = <int, int>{};
  var i = 0;
  var j = 0;
  while (i < m && j < n) {
    if (oldDigests[i] == newDigests[j]) {
      aligned[i] = j;
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }

  final usedNew = aligned.values.toSet();

  // --- 第 2 层:相同 digest 候选消歧 ---
  for (var oi = 0; oi < m; oi++) {
    if (aligned.containsKey(oi)) continue;
    final d = oldDigests[oi];
    int? best;
    var bestScore = -1;
    final prevOld = oi > 0 ? aligned[oi - 1] : null;
    final nextOld = oi < m - 1 ? aligned[oi + 1] : null;
    for (var nj = 0; nj < n; nj++) {
      if (usedNew.contains(nj) || newDigests[nj] != d) continue;
      var score = 0;
      if (prevOld != null && nj == prevOld + 1) score += 2;
      if (nextOld != null && nj == nextOld - 1) score += 2;
      if (score > bestScore) {
        bestScore = score;
        best = nj;
      }
    }
    if (best != null) {
      aligned[oi] = best;
      usedNew.add(best);
    }
  }

  // --- 第 3 层:同位置兜底 ---
  for (var oi = 0; oi < m; oi++) {
    if (aligned.containsKey(oi)) continue;
    if (oi < n && !usedNew.contains(oi)) {
      aligned[oi] = oi;
      usedNew.add(oi);
    }
  }

  return {for (var k = 0; k < m; k++) k: aligned[k]};
}

/// 外部修改文档后,把旧高亮重定位到新文档坐标。
///
/// 调用方(application 层)负责预制:
/// - [oldDigests]:旧文档(高亮所基于的版本)的段落指纹序列。
/// - [newDigests]:当前文档的段落指纹序列。
/// - [newParagraphTexts]:当前文档各段原文(段内 `indexOf` 用)。
/// - [oldParagraphSpans]:旧文档各段的全局 offset 范围(与 [oldDigests] 同序)。
///
/// `oldDigests`/`oldParagraphSpans` 与 `newDigests`/`newParagraphTexts` 必须
/// 各自同序对应同一段。段落按 `\n` 切分;段间换行不计入段落范围。
ReconcileResult reconcileHighlights({
  required List<String> oldDigests,
  required List<String> newDigests,
  required List<String> newParagraphTexts,
  required List<ParagraphSpan> oldParagraphSpans,
  required List<Highlight> oldHighlights,
}) {
  if (oldHighlights.isEmpty) return ReconcileResult.empty;

  final alignment = alignParagraphs(oldDigests, newDigests);

  // 预算新文档各段全局起点:段 i 起点 = 前 i 段长度之和 + i 个换行。
  final newParaStarts = List<int>.filled(newParagraphTexts.length, 0);
  var acc = 0;
  for (var k = 0; k < newParagraphTexts.length; k++) {
    newParaStarts[k] = acc;
    acc += newParagraphTexts[k].length + 1; // +1 for '\n'
  }

  final located = <Highlight>[];
  final lost = <Highlight>[];

  for (final h in oldHighlights) {
    final oldParaIdx = _findParagraphContaining(oldParagraphSpans, h.start);
    if (oldParaIdx < 0) {
      lost.add(h);
      continue;
    }
    final paraSpan = oldParagraphSpans[oldParaIdx];
    // 跨段高亮本版不支持,判 lost。
    if (h.end > paraSpan.end) {
      lost.add(h);
      continue;
    }
    final localStart = h.start - paraSpan.start;
    final oldParaLen = paraSpan.end - paraSpan.start;

    final newParaIdx = alignment[oldParaIdx];
    if (newParaIdx == null) {
      lost.add(h);
      continue;
    }

    final newParaText = newParagraphTexts[newParaIdx];
    final newParaStart = newParaStarts[newParaIdx];
    final newParaLen = newParaText.length;

    final anchor = h.anchorText;
    if (anchor.isEmpty) {
      // 空锚点(零长度高亮)无法验证段归属 → lost。否则整篇重写后 layer-3
      // 同位置兜底会把它误重定位到无关段(段对齐但内容全异)。
      lost.add(h);
      continue;
    }
    // 统一 indexOf 重定位:段内小改 anchor 仍在 → 唯一命中;段被替换为无关
    // 内容 → anchor 失配 lost。多次命中按旧段内比例位置消歧。
    final idx = newParaText.indexOf(anchor);
    if (idx < 0) {
      lost.add(h);
      continue;
    }
    var newLocalStart = newParaText.indexOf(anchor, idx + 1) >= 0
        ? _disambiguate(newParaText, anchor, localStart, oldParaLen)
        : idx;
    var newLocalEnd = newLocalStart + anchor.length;

    newLocalStart = newLocalStart.clamp(0, newParaLen);
    newLocalEnd = newLocalEnd.clamp(newLocalStart, newParaLen);
    if (newLocalEnd <= newLocalStart && h.end > h.start) {
      // 重定位后被夹成零(段缩空等)→ 丢失。
      lost.add(h);
      continue;
    }

    located.add(Highlight(
      id: h.id,
      start: newParaStart + newLocalStart,
      end: newParaStart + newLocalEnd,
      colorArgb: h.colorArgb,
      anchorText: newParaText.substring(newLocalStart, newLocalEnd),
    ));
  }

  return ReconcileResult(located: located, lost: lost);
}

/// 二分查找包含 [offset] 的段落索引;找不到返回 -1。
int _findParagraphContaining(List<ParagraphSpan> spans, int offset) {
  var lo = 0;
  var hi = spans.length;
  while (lo < hi) {
    final mid = (lo + hi) ~/ 2;
    if (spans[mid].end <= offset) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  if (lo >= spans.length) return -1;
  return offset < spans[lo].start ? -1 : lo;
}

/// 多次命中的锚点:按旧段内比例位置选最接近的命中点。
int _disambiguate(
  String paraText,
  String anchor,
  int oldLocalStart,
  int oldParaLen,
) {
  final hits = <int>[];
  var from = 0;
  while (true) {
    final i = paraText.indexOf(anchor, from);
    if (i < 0) break;
    hits.add(i);
    from = i + 1;
  }
  if (hits.isEmpty) return 0;
  if (hits.length == 1) return hits.first;
  final ratio = oldParaLen == 0 ? 0.0 : oldLocalStart / oldParaLen;
  final expected = (ratio * paraText.length).round();
  hits.sort((a, b) => (a - expected).abs().compareTo((b - expected).abs()));
  return hits.first;
}
