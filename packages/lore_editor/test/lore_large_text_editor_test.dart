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
              style: const EditorStyle.defaults().copyWith(
                firstLineIndent: false,
              ),
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

  testWidgets('typewriter mode scrolls to center the focused caret', (
    tester,
  ) async {
    final paragraphs = List.generate(40, (index) => '第$index段正文内容');
    final controller = LoreLargeTextController(text: paragraphs.join('\n'));
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
              style: const EditorStyle.defaults().copyWith(
                typewriterMode: true,
              ),
            ),
          ),
        ),
      ),
    );

    // 聚焦一个位于视口中下方的 block（光标在中心下方 → 应向下滚动居中）。
    await tester.tap(find.byType(TextField).at(8));
    await tester.pumpAndSettle();

    expect(scrollController.offset, greaterThan(0));
  });

  testWidgets('typewriter mode off does not auto-scroll on focus', (
    tester,
  ) async {
    final paragraphs = List.generate(40, (index) => '第$index段正文内容');
    final controller = LoreLargeTextController(text: paragraphs.join('\n'));
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

    await tester.tap(find.byType(TextField).at(8));
    await tester.pumpAndSettle();

    expect(scrollController.offset, isZero);
  });

  testWidgets('focus mode dims non-active paragraphs', (tester) async {
    final controller = LoreLargeTextController(text: '第一段\n第二段\n第三段');
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
              style: const EditorStyle.defaults().copyWith(focusMode: true),
            ),
          ),
        ),
      ),
    );

    // 聚焦中间段落 → 它保持全不透明，其余两段被 Opacity(0.28) 包裹。
    await tester.tap(find.byType(TextField).at(1));
    await tester.pumpAndSettle();

    Finder dimmedAround(int index) => find.ancestor(
      of: find.byType(TextField).at(index),
      matching: find.byWidgetPredicate(
        (widget) => widget is Opacity && widget.opacity == 0.28,
      ),
    );
    expect(dimmedAround(0).evaluate(), isNotEmpty);
    expect(dimmedAround(1).evaluate(), isEmpty);
    expect(dimmedAround(2).evaluate(), isNotEmpty);
  });

  testWidgets('focus mode follows the caret across paragraphs', (tester) async {
    final controller = LoreLargeTextController(text: '第一段\n第二段\n第三段');
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
              style: const EditorStyle.defaults().copyWith(focusMode: true),
            ),
          ),
        ),
      ),
    );

    Finder dimmedAround(int index) => find.ancestor(
      of: find.byType(TextField).at(index),
      matching: find.byWidgetPredicate(
        (widget) => widget is Opacity && widget.opacity == 0.28,
      ),
    );

    // 先聚焦第二段：第 0、2 段淡化，第 1 段高亮。
    await tester.tap(find.byType(TextField).at(1));
    await tester.pumpAndSettle();
    expect(dimmedAround(0).evaluate(), isNotEmpty);
    expect(dimmedAround(1).evaluate(), isEmpty);
    expect(dimmedAround(2).evaluate(), isNotEmpty);

    // 再点第三段：淡化应跟随光标移动——第 2 段恢复，第 1 段被淡化。
    await tester.tap(find.byType(TextField).at(2));
    await tester.pumpAndSettle();
    expect(dimmedAround(0).evaluate(), isNotEmpty);
    expect(dimmedAround(1).evaluate(), isNotEmpty);
    expect(dimmedAround(2).evaluate(), isEmpty);
  });

  testWidgets('applies the shared EditorCaret metrics to each block field', (
    tester,
  ) async {
    final controller = LoreLargeTextController(text: '第一段\n第二段');
    final scrollController = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scrollController.dispose);
    const style = EditorStyle.defaults();

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: SizedBox(
            width: 800,
            height: 500,
            child: LoreLargeTextEditor(
              controller: controller,
              scrollController: scrollController,
              style: style,
            ),
          ),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.cursorWidth, EditorCaret.width);
    expect(field.cursorHeight, EditorCaret.heightFor(style.fontSize));
    expect(field.cursorRadius, EditorCaret.radius);
    expect(field.cursorColor, isNotNull);
  });

  testWidgets('auto-indents new paragraphs when first-line indent is on', (
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

    // 缩进默认开：新段落段首自带两个全角空格。
    expect(controller.text, contains('\n　　'));
    expect(controller.blocks[1].text, '　　新段二');
  });

  testWidgets(
    'does not double-indent when Enter lands before an existing indent',
    (tester) async {
      // 第二段已带缩进；在其缩进之前（offset 0）插入换行，不应再补一组缩进。
      final controller = LoreLargeTextController(text: '甲\n　　乙');
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
      await tester.enterText(find.byType(TextField).at(1), '\n　　乙');
      await tester.pump();

      expect(controller.text, isNot(contains('　　　　')));
      expect(controller.text, contains('　　乙'));
    },
  );

  testWidgets('adds paragraph spacing only after paragraph-ending blocks', (
    tester,
  ) async {
    final controller = LoreLargeTextController(text: '第一段\n第二段');
    final scrollController = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scrollController.dispose);
    const spacing = 24.0;

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: SizedBox(
            width: 800,
            height: 500,
            child: LoreLargeTextEditor(
              controller: controller,
              scrollController: scrollController,
              style: const EditorStyle.defaults().copyWith(
                paragraphSpacing: spacing,
                firstLineIndent: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    Finder spacerAround(int index) => find.ancestor(
      of: find.byType(TextField).at(index),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Padding &&
            widget.padding is EdgeInsets &&
            (widget.padding as EdgeInsets).bottom == spacing,
      ),
    );
    // 第一段 hasLineBreak → 段末有段间距 Padding；末段无。
    expect(spacerAround(0).evaluate(), isNotEmpty);
    expect(spacerAround(1).evaluate(), isEmpty);
  });

  testWidgets('indents the empty first paragraph on mount for chapter bodies', (
    tester,
  ) async {
    // 模拟章节正文：挂载时为空。开启首行缩进 + indentFirstParagraph。
    final controller = LoreLargeTextController(text: '');
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
              indentFirstParagraph: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 首段被注入两字缩进；这样「点进首段」或「标题回车进入」时缩进已就位。
    expect(controller.text, '　　');
  });

  testWidgets('does not indent first paragraph when firstLineIndent is off', (
    tester,
  ) async {
    final controller = LoreLargeTextController(text: '');
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
              style: const EditorStyle.defaults().copyWith(
                firstLineIndent: false,
              ),
              indentFirstParagraph: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(controller.text, '');
  });

  testWidgets('does not indent first paragraph that already has content', (
    tester,
  ) async {
    final controller = LoreLargeTextController(text: '已有正文');
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
              indentFirstParagraph: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(controller.text, '已有正文');
  });

  testWidgets('arrow down moves the caret into the next paragraph', (
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
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField).first);
    controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    // 单行段落：末行即整段，↓ 跨入第二段开头（offset 4）。
    expect(controller.selection, const TextSelection.collapsed(offset: 4));
  });

  testWidgets('arrow up moves the caret into the previous paragraph', (
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
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField).at(1));
    controller.selection = const TextSelection.collapsed(offset: 4);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();

    // ↑ 从第二段开头跨回第一段同列（offset 0）。
    expect(controller.selection, const TextSelection.collapsed(offset: 0));
  });

  testWidgets('arrow down inside a wrapped line does not cross paragraphs', (
    tester,
  ) async {
    // 一段足够长、在 800 宽内会折成多视觉行的文本：行内 ↓ 应交还 TextField，
    // 不跨段（无下一段时停在末行，selection 的 block 不变）。
    final longLine = List.generate(200, (i) => '字').join();
    final controller = LoreLargeTextController(text: longLine);
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
    controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    // 仍在唯一段落内（block 0），光标下移到第二视觉行但不跨段。
    expect(
      controller.blockIndexForOffset(controller.selection.extentOffset),
      0,
    );
    expect(controller.selection.extentOffset, greaterThan(0));
  });

  testWidgets('tab inserts a full-width space at the caret', (tester) async {
    final controller = LoreLargeTextController(text: '甲乙');
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
    controller.selection = const TextSelection.collapsed(offset: 1);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(controller.text, '甲　乙');
    expect(controller.selection, const TextSelection.collapsed(offset: 2));
  });

  testWidgets('tab replaces the selection with a full-width space', (
    tester,
  ) async {
    final controller = LoreLargeTextController(text: 'abcdef');
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
    controller.selection = const TextSelection(baseOffset: 1, extentOffset: 3);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    // 选中的 'bc' 被替换为单个全角空格。
    expect(controller.text, 'a　def');
    expect(controller.selection, const TextSelection.collapsed(offset: 2));
  });

  testWidgets('shift+arrow down extends the selection across paragraphs', (
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
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField).first);
    controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    // baseOffset 保持 0，extent 跨到第二段开头（offset 4）。
    expect(
      controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: 4),
    );
  });

  testWidgets('arrow down collapses a selection before crossing paragraphs', (
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
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField).first);
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 2);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    // 非扩展的↓先折叠到 extent（offset 2），不跨段；再按一次才会跨段。
    expect(controller.selection, const TextSelection.collapsed(offset: 2));
  });
}
