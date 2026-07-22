import 'package:flutter_test/flutter_test.dart';
import 'package:lore_app/features/workspace/history_change_magnitude.dart';

void main() {
  test('相同文本变更量为 0', () {
    expect(historyChangeMagnitude('雨夜倾盆', '雨夜倾盆'), 0);
    expect(historyChangeMagnitude('abc', 'abc'), 0);
  });

  test('纯新增：空 → N 字符计为 N', () {
    expect(historyChangeMagnitude('', 'abc'), 3);
    expect(historyChangeMagnitude('', '雨夜'), 2);
  });

  test('纯删除：N 字符 → 空计为 N', () {
    expect(historyChangeMagnitude('abc', ''), 3);
  });

  test('尾部替换按删+增计', () {
    // 'abc' → 'abd'：公共前缀 'ab'（2），尾部 c/d 各计一次。
    expect(historyChangeMagnitude('abc', 'abd'), 2);
  });

  test('完全不同的两段按长度之和计', () {
    expect(historyChangeMagnitude('abc', 'xyz'), 6);
  });

  test('中文段落尾部追加只计新增部分', () {
    // '雨夜' → '雨夜倾盆'：公共前缀 '雨夜'，新增 '倾盆'（2）。
    expect(historyChangeMagnitude('雨夜', '雨夜倾盆'), 2);
  });

  test('中间插入：前后缀保留，只计插入长度', () {
    // '雨夜倾盆' → '雨夜倾盆而下'：公共前缀 '雨夜倾盆'，新增 '而下'（2）。
    expect(historyChangeMagnitude('雨夜倾盆', '雨夜倾盆而下'), 2);
  });
}
