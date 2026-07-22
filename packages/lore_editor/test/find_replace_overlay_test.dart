import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_editor/lore_editor.dart';

void main() {
  testWidgets('搜索输入框与工具按钮垂直居中', (tester) async {
    final editor = LoreTextController(text: '搜索内容');
    final findController = FindReplaceController()
      ..setPattern('搜索')
      ..recompute(editor.text);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 440,
            child: FindReplaceOverlay(
              findController: findController,
              editorController: editor,
              initialShowReplace: true,
            ),
          ),
        ),
      ),
    );

    final fieldRect = tester.getRect(
      find.byKey(const ValueKey('find-pattern-control')),
    );
    final replacementRect = tester.getRect(
      find.byKey(const ValueKey('find-replacement-control')),
    );
    expect(fieldRect.height, 32);
    expect(replacementRect.height, fieldRect.height);
    expect(replacementRect.left, fieldRect.left);
    expect(
      tester.getRect(find.byType(OutlinedButton)).height,
      fieldRect.height,
    );
    expect(tester.getRect(find.byType(FilledButton)).height, fieldRect.height);
    for (final button in tester.widgetList<IconButton>(
      find.byType(IconButton),
    )) {
      final buttonRect = tester.getRect(find.byWidget(button));
      expect(buttonRect.height, 28);
      expect(buttonRect.center.dy, closeTo(fieldRect.center.dy, 0.1));
    }
    final editableCenter = tester.getCenter(find.byType(EditableText).first);
    expect(editableCenter.dy, closeTo(fieldRect.center.dy, 0.1));

    await tester.pumpWidget(const SizedBox.shrink());
    findController.dispose();
    editor.dispose();
  });

  testWidgets('复用浮层时同步新的搜索词并重新聚焦', (tester) async {
    final editor = LoreTextController(text: '第一处 第二处');
    final first = FindReplaceController()
      ..setPattern('第一处')
      ..recompute(editor.text);
    final second = FindReplaceController()
      ..setPattern('第二处')
      ..recompute(editor.text);

    Widget build(FindReplaceController controller) {
      return MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: SizedBox(
              width: 420,
              child: FindReplaceOverlay(
                findController: controller,
                editorController: editor,
              ),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(build(first));
    await tester.pump();
    var field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, '第一处');

    await tester.pumpWidget(build(second));
    await tester.pump();
    field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, '第二处');
    expect(
      field.controller!.selection,
      const TextSelection(baseOffset: 0, extentOffset: 3),
    );
    expect(field.focusNode!.hasFocus, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    first.dispose();
    second.dispose();
    editor.dispose();
  });

  testWidgets('切换编辑器时清除旧编辑器的搜索高亮', (tester) async {
    final firstEditor = LoreLargeTextController(text: '第一处');
    final secondEditor = LoreLargeTextController(text: '第一处');
    final findController = FindReplaceController()
      ..setPattern('第一处')
      ..recompute(firstEditor.text);

    Widget build(LoreLargeTextController editor) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 440,
            child: FindReplaceOverlay(
              findController: findController,
              editorController: editor,
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(build(firstEditor));
    await tester.pump();
    expect(firstEditor.findMatches, isNotEmpty);

    await tester.pumpWidget(build(secondEditor));
    await tester.pump();
    expect(firstEditor.findMatches, isEmpty);
    expect(secondEditor.findMatches, isNotEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    findController.dispose();
    firstEditor.dispose();
    secondEditor.dispose();
  });
}
