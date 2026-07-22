import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_editor/lore_editor.dart';

void main() {
  test('tracks edits and saved versions for a long Chinese document', () {
    final text = List.filled(500000, '长').join();
    final controller = LoreTextController(text: text);
    addTearDown(controller.dispose);

    expect(controller.text.length, 500000);
    expect(controller.hasUnsavedChanges, isFalse);

    controller.text = '${controller.text}夜';

    expect(controller.editVersion, 1);
    expect(controller.hasUnsavedChanges, isTrue);
    final snapshot = controller.buildSnapshot();
    controller.markSaved(snapshot.version);
    expect(controller.hasUnsavedChanges, isFalse);

    controller.replaceFromDisk('磁盘版本');
    expect(controller.text, '磁盘版本');
    expect(controller.hasUnsavedChanges, isFalse);
  });

  test('markSaved notifies listeners so save status can refresh', () {
    final controller = LoreTextController(text: '甲');
    addTearDown(controller.dispose);
    controller.text = '${controller.text}乙';
    expect(controller.hasUnsavedChanges, isTrue);
    var notifications = 0;
    controller.addListener(() => notifications += 1);
    controller.markSaved(controller.editVersion);
    expect(controller.hasUnsavedChanges, isFalse);
    expect(notifications, 1);
  });

  test('characterCount excludes whitespace and updates on text change', () {
    final controller = LoreTextController(text: 'hello world');
    addTearDown(controller.dispose);
    expect(controller.characterCount, 10); // 'helloworld'

    controller.text = 'a b\tc\n';
    expect(controller.characterCount, 3); // 'abc'（覆盖 set value 路径）

    controller.replaceFromDisk('磁盘 版本');
    expect(controller.characterCount, 4); // '磁盘版本'（覆盖 replaceFromDisk 路径）
  });

  test('characterCount is stable across selection-only changes', () {
    final controller = LoreTextController(text: 'abc def');
    addTearDown(controller.dispose);
    expect(controller.characterCount, 6); // 'abcdef'
    final versionBefore = controller.editVersion;
    controller.selection = const TextSelection.collapsed(offset: 2);
    // 仅 selection 变化：不进 set value 的 textChanged 分支，缓存与版本都不动。
    expect(controller.characterCount, 6);
    expect(controller.editVersion, versionBefore);
  });

  test('characterCountInRange counts non-whitespace runes in a range', () {
    final controller = LoreTextController(text: '第1章 标题\n正文 内容');
    addTearDown(controller.dispose);

    // 全选：与 characterCount 同口径（非空白 rune，含标题行）。
    expect(
      controller.characterCountInRange(0, controller.text.length),
      controller.characterCount,
    );
    // 选中正文区间（含空格/换行）：去空白后 4 字（正 文 内 容）。
    final start = controller.text.indexOf('正');
    expect(controller.characterCountInRange(start, controller.text.length), 4);
    // 反向/折叠区间返回 0。
    expect(controller.characterCountInRange(3, 3), 0);
    expect(controller.characterCountInRange(9, 2), 0);
  });
}
