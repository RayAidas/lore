import 'package:lore_domain/lore_domain.dart';
import 'package:test/test.dart';

Highlight hl(
  int start,
  int end, {
  String id = 'h',
  int color = 0xFFFFD54F,
  String anchor = 'anchor',
}) {
  return Highlight(
    id: id,
    start: start,
    end: end,
    colorArgb: color,
    anchorText: anchor,
  );
}

/// 断言单条高亮(忽略 anchorText 在 shift 后不变的事实)。
void expectSingle(
  List<Highlight> actual,
  int start,
  end, {
  String id = 'h',
  int color = 0xFFFFD54F,
}) {
  expect(actual, hasLength(1));
  expect(actual.first.start, start);
  expect(actual.first.end, end);
  expect(actual.first.id, id);
  expect(actual.first.colorArgb, color);
}

void main() {
  group('shiftHighlights - 编辑在高亮外部', () {
    test('编辑完全在左侧(不相切)→ 整体右移 delta', () {
      // 删除 [5,7) 插入 3 字,高亮 [10,20) 在右侧,跟随原字右移 +1。
      final result = shiftHighlights([hl(10, 20)], at: 5, delLen: 2, addLen: 3);
      expectSingle(result, 11, 21);
    });

    test('编辑完全在右侧(不相切)→ 不动', () {
      final result = shiftHighlights(
        [hl(10, 20)],
        at: 25,
        delLen: 2,
        addLen: 3,
      );
      expectSingle(result, 10, 20);
    });

    test('编辑左相切(at==end, del>0)→ 不动', () {
      // 删除 [20,22) 恰在高亮末尾之后,不影响高亮。
      final result = shiftHighlights(
        [hl(10, 20)],
        at: 20,
        delLen: 2,
        addLen: 3,
      );
      expectSingle(result, 10, 20);
    });

    test('编辑右相切(at+del==start, del>0)→ 高亮左移填补', () {
      // 删除 [10,20),高亮 start=20 恰为删除区右边界,高亮整体左移。
      final result = shiftHighlights(
        [hl(20, 30)],
        at: 10,
        delLen: 10,
        addLen: 3,
      );
      expectSingle(result, 13, 23);
    });
  });

  group('shiftHighlights - 纯插入(delLen==0)', () {
    test('落在 start 边界 → 右端扩展', () {
      final result = shiftHighlights(
        [hl(20, 30)],
        at: 20,
        delLen: 0,
        addLen: 5,
      );
      expectSingle(result, 20, 35);
    });

    test('落在 end 边界 → 不动', () {
      final result = shiftHighlights(
        [hl(20, 30)],
        at: 30,
        delLen: 0,
        addLen: 5,
      );
      expectSingle(result, 20, 30);
    });

    test('落在严格内部 → 右端扩展', () {
      final result = shiftHighlights(
        [hl(20, 30)],
        at: 25,
        delLen: 0,
        addLen: 5,
      );
      expectSingle(result, 20, 35);
    });
  });

  group('shiftHighlights - 删除与替换', () {
    test('删除左半 → 右端收缩', () {
      // 删除 [22,26),高亮 [20,30) 末尾左移。
      final result = shiftHighlights(
        [hl(20, 30)],
        at: 22,
        delLen: 4,
        addLen: 0,
      );
      expectSingle(result, 20, 26);
    });

    test('删除右半 → 右端收缩到删除点', () {
      // 删除 [26,30),end=30 落在删除区右边界,收缩到 at=26。
      final result = shiftHighlights(
        [hl(20, 30)],
        at: 26,
        delLen: 4,
        addLen: 0,
      );
      expectSingle(result, 20, 26);
    });

    test('删除吞噬整个高亮 → 丢弃', () {
      final result = shiftHighlights(
        [hl(20, 30)],
        at: 18,
        delLen: 16,
        addLen: 0,
      );
      expect(result, isEmpty);
    });

    test('替换且 end 落在删除区内 → 收缩到删除点前(不含插入文本)', () {
      // 删除 [15,25) 插入 3 字;高亮 [10,20) 的 end=20 落在删除区内,
      // 应收缩到 at=15(残存原字符),而非延伸到 at+add=18(会包含插入文本)。
      final result = shiftHighlights(
        [hl(10, 20)],
        at: 15,
        delLen: 10,
        addLen: 3,
      );
      expectSingle(result, 10, 15);
    });

    test('替换高亮内部 → 右端按净变化调整', () {
      // 删除 [25,30) 插入 3 字,净 -2,end 从 40 → 38。
      final result = shiftHighlights(
        [hl(20, 40)],
        at: 25,
        delLen: 5,
        addLen: 3,
      );
      expectSingle(result, 20, 38);
    });
  });

  group('shiftHighlights - 多高亮', () {
    test('删除跨多个高亮 → 部分收缩、部分丢弃', () {
      // 删除 [15,45) 插入 5 字。
      // h1=[10,20):end=20 落删除区 → 收缩到 at=15,结果 [10,15)。
      // h2=[30,40):整体落入删除区 → 丢弃。
      final result = shiftHighlights(
        [hl(10, 20, id: 'h1'), hl(30, 40, id: 'h2')],
        at: 15,
        delLen: 30,
        addLen: 5,
      );
      expect(result, hasLength(1));
      expect(result.first.id, 'h1');
      expect(result.first.start, 10);
      expect(result.first.end, 15);
    });
  });

  group('shiftHighlights - 零长度高亮', () {
    test('纯插入恰在零长度位置 → 保持零长度', () {
      final result = shiftHighlights(
        [hl(15, 15)],
        at: 15,
        delLen: 0,
        addLen: 5,
      );
      expectSingle(result, 15, 15);
    });

    test('零长度落在删除区内 → 塌缩到删除区边界,保持零长度', () {
      // 删除 [10,20),零高亮在 15 → 塌缩到 at+add=10。
      final result = shiftHighlights(
        [hl(15, 15)],
        at: 10,
        delLen: 10,
        addLen: 0,
      );
      expectSingle(result, 10, 10);
    });

    test('零长度在删除区之后 → 平移', () {
      final result = shiftHighlights(
        [hl(25, 25)],
        at: 10,
        delLen: 5,
        addLen: 2,
      );
      expectSingle(result, 22, 22);
    });
  });

  group('shiftHighlights - 不变量', () {
    test('空列表 → 空列表', () {
      expect(shiftHighlights([], at: 0, delLen: 0, addLen: 5), isEmpty);
    });

    test('保留 id / colorArgb / anchorText', () {
      final result = shiftHighlights(
        [hl(10, 20, id: 'x', color: 0xFFA5D6A7, anchor: '原始锚点')],
        at: 5,
        delLen: 0,
        addLen: 3,
      );
      expectSingle(result, 13, 23, id: 'x', color: 0xFFA5D6A7);
      expect(result.first.anchorText, '原始锚点');
    });
  });
}
