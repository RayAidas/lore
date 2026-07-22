import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

final class EditorTextSnapshot {
  const EditorTextSnapshot({required this.text, required this.version});

  final String text;
  final int version;
}

abstract interface class LoreDocumentController implements Listenable {
  String get text;

  set text(String value);

  /// 文档长度（UTF-16 码元数）。必须是 O(1)——消费方（如查找面板）会在
  /// 每次按键的回调里读取它来决定走同步还是异步路径，不能物化整串文本。
  int get length;

  TextSelection get selection;

  set selection(TextSelection value);

  int get editVersion;

  int get savedVersion;

  int get characterCount;

  /// `[start, end)` 区间内的非空白 rune 数，与 [characterCount] 同口径
  /// （非空白 rune，含标题行）。用于状态栏「选中字数」，保证全选时与
  /// [characterCount] 相等。
  ///
  /// `end <= start`（折叠或反向选区）时直接返回 0，**不**校验越界；其余情况下
  /// `start`/`end` 须落在 `[0, length]`，否则抛 [RangeError]。
  int characterCountInRange(int start, int end);

  bool get hasUnsavedChanges;

  bool get canUndo;

  bool get canRedo;

  EditorTextSnapshot buildSnapshot();

  void markSaved(int version);

  void replaceFromDisk(
    String text, {
    TextSelection? selection,
    bool markSaved = true,
  });

  void replaceAllText(String text, {TextSelection? selection});

  void undo();

  void redo();

  void dispose();
}
