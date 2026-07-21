import 'highlight.dart';

/// 编辑发生后,把高亮 offset 重映射到新文档坐标。
///
/// 编辑语义:文档区间 `[at, at + delLen)` 被替换为长度 `addLen` 的新文本。
/// 所有参数非负。核心原则是 **高亮始终跟随它原本覆盖的字符**:编辑让原字符
/// 迁移到新位置,高亮跟着迁过去。
///
/// 区间 `[start, end)` 的两端用不同的边界归属映射,这是正确处理"删除覆盖高亮
/// 一部分"的关键:
///
/// - **start(左偏)**:落在删除区内 → 跳到插入区右端 `at + addLen`。高亮起点的
///   原字符已被删,从新插入文本之后重新立足。
/// - **end(右偏)**:落在删除区内 → 收缩到删除区左端 `at`。高亮末尾被截断,只
///   保留删除点之前的残存原字符,不含新插入文本。
///
/// 两端在编辑点之前(`x <= at`)不动,在删除区之后(`x > at + delLen`)平移
/// `addLen - delLen`。这让:
/// - 纯插入 `at == start` → 右端扩展(批注起点处加字,原字右移、批注跟随长);
/// - 纯插入 `at == end` → 不动(批注外追加);
/// - 纯插入落在严格内部 → 扩展;
/// - 删除覆盖中间 → 收缩;
/// - 删除吞噬整体 → 丢弃。
///
/// `anchorText` 不在此函数修改——它只在持久化时由调用方用 `text.substring`
/// 刷新(必须反映"上次落盘"的内容才能检测后续漂移)。
List<Highlight> shiftHighlights(
  List<Highlight> highlights, {
  required int at,
  required int delLen,
  required int addLen,
}) {
  if (highlights.isEmpty) return const [];
  assert(at >= 0 && delLen >= 0 && addLen >= 0);

  int mapStart(int x) {
    if (x <= at) return x;
    if (x <= at + delLen) return at + addLen;
    return x - delLen + addLen;
  }

  int mapEnd(int x) {
    if (x <= at) return x;
    if (x <= at + delLen) return at;
    return x - delLen + addLen;
  }

  final result = <Highlight>[];
  for (final h in highlights) {
    final newStart = mapStart(h.start);
    // 零长度高亮:保持零长度,跟随 start 映射即可(两端不可分裂)。
    final newEnd = h.isCollapsed ? newStart : mapEnd(h.end);
    // 非零长度高亮被压成零(整体落入删除区,被删穿)→ 丢弃。
    if (!h.isCollapsed && newEnd <= newStart) continue;
    result.add(h.copyWith(start: newStart, end: newEnd));
  }
  return result;
}
