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
                // 打字机居中滚动与段间距/行高相关：显式 pin 住，使「第 8 段位于
                // 视口中线下方」这一前提不被默认排版基线（现 1.45/14）的后续
                // 调整改写，让本用例聚焦滚动行为本身，而非默认间距。
                lineHeight: 1.5,
                paragraphSpacing: 12,
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

  testWidgets('arrow down into an off-screen paragraph scrolls it into view', (
    tester,
  ) async {
    // 首段超长（远超视口 + cacheExtent），使其后的短段初始在视口外、未被
    // ListView 构建——这正是 P3 的触发场景（model selection 移走但焦点脱节）。
    final longFirst = List.filled(1500, '字').join();
    final controller = LoreLargeTextController(text: '$longFirst\n第二段\n第三段');
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
    await tester.pumpAndSettle();

    // 聚焦首段末尾（末视觉行在视口下方），按↓应跨到第二段。
    await tester.tap(find.byType(TextField).first);
    controller.selection = TextSelection.collapsed(offset: longFirst.length);
    await tester.pumpAndSettle();
    final offsetBefore = scrollController.offset;

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    // model 与焦点都跟到第二段，无脱节。
    expect(
      controller.blockIndexForOffset(controller.selection.extentOffset),
      1,
    );
    // 兜底粗滚触发：目标段原本未渲染，滚动使其构建，offset 增大。
    expect(scrollController.offset, greaterThan(offsetBefore));
  });

  testWidgets(
    'typewriter mode recenters the off-screen target after crossing',
    (tester) async {
      // 同样的超长首段场景，但开打字机模式。回归：focusAt 后必须用目标段
      // caret 居中（而非依赖 focusAt 之前 _handleControllerChanged 的早 recenter
      // 居中原段边缘），否则 typewriter「光标居中」语义在跨到未渲染段时失效。
      final longFirst = List.filled(1500, '字').join();
      final controller = LoreLargeTextController(text: '$longFirst\n第二段\n第三段');
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
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TextField).first);
      controller.selection = TextSelection.collapsed(offset: longFirst.length);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      // 跨到第二段（model 与焦点一致）；typewriter 模式下 focusAt 前后的两次
      // recenter 不应破坏跨段或抛异常。
      expect(
        controller.blockIndexForOffset(controller.selection.extentOffset),
        1,
      );
      // 目标段原本未渲染，跨段后粗滚 + 居中发生，offset 非零（光标被带入视口）。
      expect(scrollController.offset, greaterThan(0));
    },
  );

  testWidgets('long-pressing arrow right crosses into the next paragraph', (
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

    // 长按 →：1 个 down + 3 个 repeat。前 3 次行内右移到段末（offset 3），
    // 第 4 次（repeat）在段末应跨段到第二段——修复前 repeat 被
    // handleBoundaryKey 忽略，光标卡在段末无法跨段（与单次点按不一致）。
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(
      controller.blockIndexForOffset(controller.selection.extentOffset),
      1,
    );
  });

  testWidgets('long-pressing arrow down crosses paragraphs', (tester) async {
    final controller = LoreLargeTextController(text: '一\n二\n三');
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

    // 长按 ↓：down 跨 一→二，repeat 跨 二→三。贴合用户报告的「上下长按不跨段」，
    // 覆盖 _handleVerticalKey 的 repeat 路径（与 ←/→ 的跨段实现不同）。
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(
      controller.blockIndexForOffset(controller.selection.extentOffset),
      2,
    );
  });

  testWidgets('header scrolls together with the body content', (tester) async {
    // header 作为滚动视口首个 sliver 注入，应随正文一起滚动，而非固定钉顶。
    final paragraphs = List.generate(80, (index) => '第$index段正文内容');
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
              header: const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Text('章节标题'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 标题初始可见、位于视口顶部，且在首个正文块之上（首个 sliver）。
    final headerRectBefore = tester.getRect(find.text('章节标题'));
    expect(headerRectBefore.top, greaterThanOrEqualTo(0));
    expect(
      headerRectBefore.center.dy,
      lessThan(tester.getCenter(find.byType(TextField).first).dy),
    );

    // 向下滚动：标题应同步上移相同位移，证明它参与滚动（非固定 header）。
    const delta = 40.0;
    scrollController.jumpTo(delta);
    await tester.pumpAndSettle();

    final headerRectAfter = tester.getRect(find.text('章节标题'));
    expect(headerRectAfter.top, lessThan(headerRectBefore.top));
    // 位移量与滚动量一致（±2px 容差吸收亚像素取整）。
    expect(
      (headerRectBefore.top - headerRectAfter.top) - delta,
      lessThanOrEqualTo(2),
    );
  });

  testWidgets(
    'header widget stays tappable through the editor pointer listener',
    (tester) async {
      // 编辑器用 translucent Listener 观察指针做选中拖拽；header 内的可聚焦控件
      // （如副标题 TextField）不应被 Listener 吞掉点击，应正常获焦。
      final controller = LoreLargeTextController(text: '正文段落一\n正文段落二');
      final scrollController = ScrollController();
      final headerController = TextEditingController();
      final headerFocus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(scrollController.dispose);
      addTearDown(headerController.dispose);
      addTearDown(headerFocus.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: SizedBox(
              width: 800,
              height: 500,
              child: LoreLargeTextEditor(
                controller: controller,
                scrollController: scrollController,
                header: TextField(
                  controller: headerController,
                  focusNode: headerFocus,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(headerFocus.hasFocus, isFalse);
      // header 的 TextField 是树序首个（首个 sliver）。
      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();

      expect(headerFocus.hasPrimaryFocus, isTrue);
    },
  );

  testWidgets('renders grid lines per paragraph without breaking editing', (
    tester,
  ) async {
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
              style: const EditorStyle.defaults().copyWith(
                gridLineMode: GridLineMode.dashed,
                firstLineIndent: false,
              ),
              autofocus: true,
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, '改第一段');
    await tester.pump();

    expect(controller.text, '改第一段\n第二段\n第三段');
    // 每段 block 至少含一个网格线 CustomPaint 与一个选区 CustomPaint。
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets(
    'grid line layer mounts only for non-none mode and skips first paragraph '
    'top',
    (tester) async {
      // 直接定位网格 painter（私有类，按 runtimeType 匹配）；drawTopLine 经
      // dynamic 读取——若类被重命名，本测试需同步更新。
      Finder gridPainters() => find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter?.runtimeType.toString() == '_BlockGridLinePainter',
      );

      final controller = LoreLargeTextController(text: '第一段\n第二段');
      final scrollController = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(scrollController.dispose);

      Widget build(GridLineMode mode) => MaterialApp(
        home: Material(
          child: SizedBox(
            width: 800,
            height: 500,
            child: LoreLargeTextEditor(
              controller: controller,
              scrollController: scrollController,
              style: const EditorStyle.defaults().copyWith(
                gridLineMode: mode,
                firstLineIndent: false,
              ),
            ),
          ),
        ),
      );

      // none：网格层完全不挂载（`if (mode != none)` 守卫生效）。
      await tester.pumpWidget(build(GridLineMode.none));
      await tester.pumpAndSettle();
      expect(gridPainters(), findsNothing);

      // solid：每段一个网格 painter；首段顶部线关闭、第二段开启。
      await tester.pumpWidget(build(GridLineMode.solid));
      await tester.pumpAndSettle();
      final painters = gridPainters();
      expect(painters.evaluate().length, 2);
      final firstPainter =
          (tester.widget(painters.at(0)) as CustomPaint).painter as dynamic;
      final secondPainter =
          (tester.widget(painters.at(1)) as CustomPaint).painter as dynamic;
      expect(firstPainter.drawTopLine, isFalse);
      expect(secondPainter.drawTopLine, isTrue);
    },
  );

  testWidgets('focus mode focuses a tapped paragraph on the first tap', (
    tester,
  ) async {
    // 回归：专注模式下点击淡化段，首次点击即应落光标。修复前以 widget.dimmed
    // 条件增删 Opacity 包裹——淡化↔恢复切换会改变 Focus 子树的类型，Flutter
    // 随之重建 content 子树（含 TextField 与其 _focusNode），把刚刚 requestFocus
    // 的焦点丢弃，表现为「点击段落只激活却不落光标、需要重复点击」。
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

    // 初始 selection 在末尾（block 2 激活、未淡化），block 1 被淡化。点 block 1。
    await tester.tap(find.byType(TextField).at(1));
    await tester.pumpAndSettle();

    // block 1 首次点击即获焦（光标可见）：其 focusNode 持有焦点、未被重建丢弃。
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).focusNode!.hasFocus,
      isTrue,
    );
  });

  testWidgets('focus mode arrow down traverses a multi-line paragraph', (
    tester,
  ) async {
    // 回归：专注模式下方向键跨入多行段后应能继续移动，不卡住。根因同上——跨段
    // 触发目标段淡化↔恢复重建，焦点丢失，后续方向键无 block 获焦而失效。
    final long = List.generate(200, (i) => '字').join();
    final controller = LoreLargeTextController(text: '短一\n$long\n末段');
    final scrollController = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scrollController.dispose);

    // selection 置于首段开头：挂载即 active=block 0，autofocus 让 block 0 获焦，
    // 避免点击本身触发淡化切换（那会先踩到本 bug）。
    controller.selection = const TextSelection.collapsed(offset: 0);
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
              style: const EditorStyle.defaults().copyWith(focusMode: true),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.blockIndexForOffset(controller.selection.extentOffset), 0);

    // ↓：单行 block 0 跨入多行 block 1。
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(controller.blockIndexForOffset(controller.selection.extentOffset), 1);
    final crossedOffset = controller.selection.extentOffset;

    // 再 ↓：焦点应已落到 block 1，光标在多行段内下移一行（extent 增大），不卡住。
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(controller.selection.extentOffset, greaterThan(crossedOffset));
  });

  testWidgets('focus mode autofocus lands on a non-dimmed block', (tester) async {
    final controller = LoreLargeTextController(text: '第一段\n第二段\n第三段\n第四段');
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
              style: const EditorStyle.defaults().copyWith(focusMode: true),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 挂载即 autofocus：被聚焦的段必须是非淡化段（光标可见）。修复前 autofocus 恒落
    // block 0，而初始 selection 在末段、active=末段，于是 block 0 被淡化——光标起始于
    // 几乎不可见（0.28）的淡化段，表现为「专注模式打开就看不到光标，要点一下才出现」。
    final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    final focusedIndex = fields.indexWhere(
      (f) => f.focusNode?.hasFocus ?? false,
    );
    expect(focusedIndex, greaterThanOrEqualTo(0));
    final dimmedAncestor = find.ancestor(
      of: find.byType(TextField).at(focusedIndex),
      matching: find.byWidgetPredicate(
        (widget) => widget is Opacity && widget.opacity == 0.28,
      ),
    );
    expect(dimmedAncestor.evaluate(), isEmpty);
  });
}
