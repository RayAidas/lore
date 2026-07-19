import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_editor/lore_editor.dart';

void main() {
  testWidgets('builds only visible paragraph fields', (tester) async {
    final controller = LoreLargeTextController(
      text: List.generate(5000, (index) => '第$index段正文').join('\n'),
    );
    final scrollController = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: SizedBox(
            width: 800,
            height: 500,
            child: LoreLargeTextEditor(
              controller: controller,
              scrollController: scrollController,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(TextField), findsWidgets);
    expect(find.byType(TextField).evaluate().length, lessThan(50));
  });

  testWidgets('writes visible field edits into the document buffer', (
    tester,
  ) async {
    final controller = LoreLargeTextController(text: '旧段落\n下一段');
    final scrollController = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: SizedBox(
            width: 800,
            height: 500,
            child: LoreLargeTextEditor(
              controller: controller,
              scrollController: scrollController,
              autofocus: true,
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, '新的段落');
    await tester.pump();

    expect(controller.text, '新的段落\n下一段');
    expect(controller.hasUnsavedChanges, isTrue);
  });

  testWidgets('splits a paragraph when input inserts a newline', (
    tester,
  ) async {
    final controller = LoreLargeTextController(text: '原段落\n末段');
    final scrollController = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: SizedBox(
            width: 800,
            height: 500,
            child: LoreLargeTextEditor(
              controller: controller,
              scrollController: scrollController,
              autofocus: true,
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, '新段一\n新段二');
    await tester.pump();

    expect(controller.text, '新段一\n新段二\n末段');
    expect(controller.blocks.map((block) => block.text), ['新段一', '新段二', '末段']);
    expect(controller.selection, const TextSelection.collapsed(offset: 7));
    expect(
      controller.blockIndexForOffset(controller.selection.extentOffset),
      1,
    );
  });

  testWidgets('does not commit active IME composing text', (tester) async {
    final controller = LoreLargeTextController(text: '旧');
    final scrollController = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: SizedBox(
            width: 800,
            height: 500,
            child: LoreLargeTextEditor(
              controller: controller,
              scrollController: scrollController,
              autofocus: true,
            ),
          ),
        ),
      ),
    );
    await tester.showKeyboard(find.byType(TextField).first);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '拼',
        selection: TextSelection.collapsed(offset: 1),
        composing: TextRange(start: 0, end: 1),
      ),
    );
    await tester.pump();
    expect(controller.text, '旧');
    expect(controller.hasUnsavedChanges, isFalse);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '拼',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    await tester.pump();
    expect(controller.text, '拼');
    expect(controller.hasUnsavedChanges, isTrue);
  });

  testWidgets('moves the caret across paragraph boundaries', (tester) async {
    final controller = LoreLargeTextController(text: '第一段\n第二段');
    final scrollController = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: SizedBox(
            width: 800,
            height: 500,
            child: LoreLargeTextEditor(
              controller: controller,
              scrollController: scrollController,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField).first);
    controller.selection = const TextSelection.collapsed(offset: 3);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(controller.selection, const TextSelection.collapsed(offset: 4));
  });

  testWidgets('keeps command-a selection across all paragraphs', (
    tester,
  ) async {
    final controller = LoreLargeTextController(text: '第一段\n第二段');
    final scrollController = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: SizedBox(
            width: 800,
            height: 500,
            child: LoreLargeTextEditor(
              controller: controller,
              scrollController: scrollController,
              autofocus: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.length,
    );
    await tester.pump();

    expect(controller.selection.start, 0);
    expect(controller.selection.end, controller.length);
    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(
      fields.first.controller!.selection,
      const TextSelection(baseOffset: 0, extentOffset: 3),
    );
    expect(
      fields.elementAt(1).controller!.selection,
      const TextSelection(baseOffset: 0, extentOffset: 3),
    );
  });

  testWidgets('handles the macOS command-a key sequence globally', (
    tester,
  ) async {
    final controller = LoreLargeTextController(text: '第一段\n第二段');
    final scrollController = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: SizedBox(
            width: 800,
            height: 500,
            child: LoreLargeTextEditor(
              controller: controller,
              scrollController: scrollController,
              autofocus: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(controller.selection.start, 0);
    expect(controller.selection.end, controller.length);
  });

  testWidgets('keeps mouse drag selection in global offsets', (tester) async {
    final controller = LoreLargeTextController(text: '第一段\n第二段');
    final scrollController = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: SizedBox(
            width: 800,
            height: 500,
            child: LoreLargeTextEditor(
              controller: controller,
              scrollController: scrollController,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final fields = find.byType(TextField);
    final start = tester.getTopLeft(fields.first) + const Offset(2, 8);
    final end = tester.getBottomRight(fields.last) - const Offset(2, 8);
    await tester.dragFrom(start, end - start);
    await tester.pump();

    expect(controller.selection.start, 0);
    expect(controller.selection.end, controller.length);
  });

  testWidgets('replaces the whole TXT selection when typing', (tester) async {
    final controller = LoreLargeTextController(text: '第一段\n第二段');
    final scrollController = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: SizedBox(
            width: 800,
            height: 500,
            child: LoreLargeTextEditor(
              controller: controller,
              scrollController: scrollController,
              autofocus: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.length,
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '替换全文');
    await tester.pump();

    expect(controller.text, '替换全文');
  });

  testWidgets('replaces only a partial selection when typing', (tester) async {
    final controller = LoreLargeTextController(text: 'abc\ndef');
    final scrollController = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: SizedBox(
            width: 800,
            height: 500,
            child: LoreLargeTextEditor(
              controller: controller,
              scrollController: scrollController,
              autofocus: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    controller.selection = const TextSelection(baseOffset: 1, extentOffset: 2);
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'aXc');
    await tester.pump();

    expect(controller.text, 'aXc\ndef');
  });

  testWidgets('native backspace removes a complete emoji', (tester) async {
    final controller = LoreLargeTextController(text: 'a😀b');
    final scrollController = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: SizedBox(
            width: 800,
            height: 500,
            child: LoreLargeTextEditor(
              controller: controller,
              scrollController: scrollController,
              autofocus: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    controller.selection = const TextSelection.collapsed(offset: 3);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(controller.text, 'ab');
  });
}
