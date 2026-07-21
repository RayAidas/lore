import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_editor/lore_editor.dart';

void main() {
  test('edits one block and preserves global offsets', () {
    final controller = LoreLargeTextController(text: '第一段\n第二段');
    addTearDown(controller.dispose);

    controller.replaceBlockRange(
      1,
      0,
      3,
      '新的第二段',
      const TextSelection.collapsed(offset: 5),
    );

    expect(controller.text, '第一段\n新的第二段');
    expect(controller.selection.extentOffset, 9);
    expect(controller.characterCount, 8);
    expect(controller.canUndo, isTrue);

    controller.undo();
    expect(controller.text, '第一段\n第二段');
    controller.redo();
    expect(controller.text, '第一段\n新的第二段');
  });

  test('locates blocks in a million-character document', () {
    final text = List.generate(10000, (index) => '第$index段内容').join('\n');
    final controller = LoreLargeTextController(text: text);
    addTearDown(controller.dispose);

    final offset = text.lastIndexOf('第9999段');
    final block = controller.blockIndexForOffset(offset);

    expect(block, 9999);
    expect(controller.blockStart(block), offset);
  });

  test('keeps the caret in the newly created paragraph after splitting', () {
    final controller = LoreLargeTextController(text: '甲乙');
    addTearDown(controller.dispose);

    controller.selection = const TextSelection.collapsed(offset: 1);
    controller.replaceSelection('\n');

    expect(controller.text, '甲\n乙');
    expect(controller.selection, const TextSelection.collapsed(offset: 2));
    expect(controller.blockIndexForOffset(2), 1);
  });

  test('deletes paragraph separators in both directions', () {
    final controller = LoreLargeTextController(text: '第一段\n第二段');
    addTearDown(controller.dispose);

    controller.selection = const TextSelection.collapsed(offset: 4);
    controller.replaceRange(3, 4, '');
    expect(controller.text, '第一段第二段');

    controller.replaceFromDisk('第一段\n第二段', markSaved: false);
    controller.selection = const TextSelection.collapsed(offset: 3);
    controller.replaceRange(3, 4, '');
    expect(controller.text, '第一段第二段');
  });

  test('select all spans the complete document', () {
    final controller = LoreLargeTextController(text: '第一段\n第二段');
    addTearDown(controller.dispose);

    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.length,
    );

    expect(controller.selection.start, 0);
    expect(controller.selection.end, controller.length);
  });

  test('does not split surrogate pairs at block boundaries', () {
    final prefix = List.filled(8191, '长').join();
    final controller = LoreLargeTextController(text: '$prefix😀结尾');
    addTearDown(controller.dispose);

    expect(controller.blocks, hasLength(2));
    expect(controller.blocks.first.text, prefix);
    expect(controller.blocks.last.text, '😀结尾');
  });

  test('structural edits preserve unrelated block instances', () {
    final controller = LoreLargeTextController(text: '第一段\n第二段\n第三段');
    addTearDown(controller.dispose);
    final untouched = controller.blocks.last;

    controller.replaceRange(1, 1, '\n');

    expect(controller.text, '第\n一段\n第二段\n第三段');
    expect(identical(controller.blocks.last, untouched), isTrue);
  });

  test('keeps million-character structural edits bounded', () {
    final paragraph = List.filled(99, '长').join();
    final text = List.generate(10000, (_) => '$paragraph\n').join();
    final controller = LoreLargeTextController(text: text);
    addTearDown(controller.dispose);
    final stopwatch = Stopwatch()..start();

    for (var index = 0; index < 100; index += 1) {
      controller.replaceRange(index * 2, index * 2, '\n');
    }
    stopwatch.stop();

    expect(controller.length, text.length + 100);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)));
  });

  test('matches a string model under random structural edits', () {
    final random = Random(73);
    var reference = '第一段\n第二段\n第三段';
    final controller = LoreLargeTextController(text: reference);
    addTearDown(controller.dispose);

    for (var iteration = 0; iteration < 500; iteration += 1) {
      final start = random.nextInt(reference.length + 1);
      final end = start + random.nextInt(reference.length - start + 1);
      final replacements = ['', '字', '\n', '新\n段'];
      final replacement = replacements[random.nextInt(replacements.length)];
      reference =
          reference.substring(0, start) +
          replacement +
          reference.substring(end);
      controller.replaceRange(start, end, replacement);

      expect(controller.text, reference);
      final rendered = controller.blocks
          .map((block) => block.text + (block.hasLineBreak ? '\n' : ''))
          .join();
      expect(rendered, reference);
      for (var index = 0; index < controller.blocks.length; index += 1) {
        final expectedStart = controller.blocks
            .take(index)
            .fold(0, (sum, block) => sum + block.documentLength);
        expect(controller.blockStart(index), expectedStart);
      }
    }
  });

  test('keeps million-character edits within a bounded time', () {
    final paragraph = List.filled(99, '长').join();
    final text = List.generate(10000, (_) => '$paragraph\n').join();
    final stopwatch = Stopwatch()..start();
    final controller = LoreLargeTextController(text: text);
    addTearDown(controller.dispose);

    for (var index = 0; index < 500; index += 1) {
      controller.replaceBlockRange(
        0,
        index,
        index,
        '新',
        TextSelection.collapsed(offset: index + 1),
      );
    }
    stopwatch.stop();

    expect(controller.length, text.length + 500);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
  });

  test('bounds undo memory by total character budget', () {
    // 每段 50001 字符，连续在文档最前面插入 100 段（非连续位置 → 不触发
    // typing-merge，每段是独立 undo 记录）。总量约 5M，超过 4M 字符预算，
    // 最早的若干段会被淘汰，撤销到底也无法回到空文档。
    final chunk = '${List.filled(50000, '字').join()}\n';
    final controller = LoreLargeTextController(text: '');
    addTearDown(controller.dispose);
    for (var i = 0; i < 100; i += 1) {
      controller.replaceRange(0, 0, chunk);
    }
    expect(controller.canUndo, isTrue);
    while (controller.canUndo) {
      controller.undo();
    }
    expect(controller.text, isNotEmpty);
  });

  test(
    'prependSilently inserts a prefix without marking dirty or recording undo',
    () {
      final controller = LoreLargeTextController(text: '正文');
      addTearDown(controller.dispose);
      controller.markSaved(controller.editVersion);
      expect(controller.hasUnsavedChanges, isFalse);
      expect(controller.canUndo, isFalse);

      controller.prependSilently('　　');

      expect(controller.text, '　　正文');
      // 不标脏（savedVersion 跟进）→ 不会触发自动保存重写磁盘。
      expect(controller.hasUnsavedChanges, isFalse);
      // 不记 undo → Cmd+Z 不会撤销这次注入。
      expect(controller.canUndo, isFalse);

      // 幂等：文档已以缩进开头则不动。
      controller.prependSilently('　　');
      expect(controller.text, '　　正文');

      controller.undo();
      expect(controller.text, '　　正文');
    },
  );
}
