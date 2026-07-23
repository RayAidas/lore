/// 子序列模糊匹配结果,供「快速打开」面板筛选与高亮使用。
class QuickOpenMatch {
  const QuickOpenMatch(this.score, this.matchedIndices);

  /// 匹配得分,越高越相关。综合考虑连续匹配、词首字符、靠前位置。
  final double score;

  /// [fuzzyMatch] 的 target 中被匹配到的字符下标(升序),用于高亮。
  /// 下标基于原 target(大小写不改变字符位置,可直接用于高亮原串)。
  final List<int> matchedIndices;
}

/// 大小写不敏感的**子序列**模糊匹配 + 打分。
///
/// query 的每个字符按顺序在 target 中找到即视为匹配(VSCode 风格子序列匹配)。
/// query 为空或 target 无法包含 query 子序列时返回 `null`。
/// 打分倾向:连续匹配、词首字符(紧跟 `/ _ - . \ 空格` 或位于串首)、靠前位置。
QuickOpenMatch? fuzzyMatch(String query, String target) {
  if (query.isEmpty) {
    return null;
  }
  final q = query.toLowerCase();
  final t = target.toLowerCase();
  final matched = <int>[];
  var ti = 0;
  for (var qi = 0; qi < q.length; qi++) {
    final ch = q.codeUnitAt(qi);
    var found = -1;
    while (ti < t.length) {
      if (t.codeUnitAt(ti) == ch) {
        found = ti;
        ti++;
        break;
      }
      ti++;
    }
    if (found < 0) {
      return null;
    }
    matched.add(found);
  }

  var score = 0.0;
  var prev = -1;
  for (final idx in matched) {
    var bonus = 1.0;
    if (prev >= 0 && idx == prev + 1) {
      // 连续匹配奖励。
      bonus += 0.6;
    }
    final isWordStart = idx == 0 || _isSeparator(t.codeUnitAt(idx - 1));
    if (isWordStart) {
      // 词首字符奖励(如路径段、章节号后第一个字)。
      bonus += 0.5;
    }
    // 靠前奖励:越靠前越相关。
    bonus += (1.0 - idx / t.length) * 0.3;
    score += bonus;
    prev = idx;
  }
  // 整体前缀奖励:首个字符命中串首(强前缀信号)。
  if (matched.isNotEmpty && matched.first == 0) {
    score += 1.0;
  }
  return QuickOpenMatch(score, matched);
}

bool _isSeparator(int codeUnit) {
  switch (codeUnit) {
    case 0x2F: // /
    case 0x5C: // \
    case 0x5F: // _
    case 0x2D: // -
    case 0x2E: // .
    case 0x20: // space
      return true;
    default:
      return false;
  }
}
