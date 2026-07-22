/// 两段文本的近似变更量：公共前后缀剥离后的增删字符数。O(n)。
///
/// 用于历史快照的变更量阈值判定（自上次快照后净改了多少字符），不要求
/// 精确编辑距离——单次替换按「删 + 增」计。
int historyChangeMagnitude(String a, String b) {
  final minLen = a.length < b.length ? a.length : b.length;
  var prefix = 0;
  while (prefix < minLen && a.codeUnitAt(prefix) == b.codeUnitAt(prefix)) {
    prefix += 1;
  }
  var suffix = 0;
  while (
    suffix < minLen - prefix &&
    a.codeUnitAt(a.length - 1 - suffix) == b.codeUnitAt(b.length - 1 - suffix)
  ) {
    suffix += 1;
  }
  return (a.length - prefix - suffix) + (b.length - prefix - suffix);
}
