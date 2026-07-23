import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      const TextSelection.collapsed(offset: 3),
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

  testWidgets('查找输入框聚焦时按 Esc 关闭浮层', (tester) async {
    final editor = LoreTextController(text: '查找内容');
    final findController = FindReplaceController()
      ..setPattern('查找')
      ..recompute(editor.text);
    var closeCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 440,
            child: FindReplaceOverlay(
              findController: findController,
              editorController: editor,
              onClose: () => closeCount++,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 模拟 ⌘F 打开后焦点落在查找输入框。
    await tester.tap(find.byKey(const ValueKey('find-pattern-control')));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byType(TextField).first)
          .focusNode!
          .hasFocus,
      isTrue,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(closeCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    findController.dispose();
    editor.dispose();
  });

  testWidgets('查找跳转后焦点保持在搜索框（编辑器抢焦被覆盖）', (tester) async {
    final editor = LoreLargeTextController(text: 'abc def abc');
    final findController = FindReplaceController()
      ..setPattern('abc')
      ..recompute(editor.text);
    final patternFocus = FocusNode(debugLabel: 'thief');
    addTearDown(patternFocus.dispose);

    // 模拟 LoreLargeTextEditor 的 reveal 行为：仅在 requestReveal 递增 revealSeq
    // 时把焦点抢到段落 block（thief 节点）——真实编辑器用 revealChanged 守卫，
    // setFindMatches 等其它 notify 不会抢焦。注册时机与真实编辑器一致：在
    // controller notify 的同步链中入队 postFrame，早于 overlay 的 re-focus，
    // 从而构成「抢焦→拉回」的对抗场景。
    var lastRevealSeq = editor.revealSeq;
    void stealFocus() {
      final seq = editor.revealSeq;
      if (seq == lastRevealSeq) {
        return;
      }
      lastRevealSeq = seq;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        patternFocus.requestFocus();
      });
    }

    editor.addListener(stealFocus);
    addTearDown(() => editor.removeListener(stealFocus));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 440,
            child: Column(
              children: [
                FindReplaceOverlay(
                  findController: findController,
                  editorController: editor,
                ),
                Focus(focusNode: patternFocus, child: const SizedBox.shrink()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final patternField = tester
        .widget<TextField>(find.byType(TextField).first)
        .focusNode!;
    expect(
      patternField.hasFocus,
      isTrue,
      reason: 'cmd+F 打开（选中文字填入）后焦点应在搜索框，而非被编辑器抢走',
    );

    // 模拟按「下一个」：编辑器会再次抢焦，overlay 应再次拉回。
    findController.next();
    await tester.pumpAndSettle();
    expect(patternField.hasFocus, isTrue, reason: '跳转下一个匹配后焦点仍应在搜索框');

    findController.previous();
    await tester.pumpAndSettle();
    expect(patternField.hasFocus, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    findController.dispose();
    editor.dispose();
  });

  testWidgets('跨段多帧抢焦（编辑器重试聚焦）后焦点仍回到搜索框', (tester) async {
    final editor = LoreLargeTextController(text: 'abc def\n' * 80);
    final findController = FindReplaceController()
      ..setPattern('abc')
      ..recompute(editor.text);
    final thief = FocusNode(debugLabel: 'thief');
    addTearDown(thief.dispose);

    // 模拟 _ensureBlockVisibleAndFocus 的跨帧重试链：revealSeq 变化后连续 5 帧
    // （对应 depth 0..4）每帧 requestFocus 抢焦——比单帧抢焦更接近真实跨段远跳，
    // 单次 re-focus 会被后续帧再次抢走（C1 回归守护）。
    var lastRevealSeq = editor.revealSeq;
    void stealFocus() {
      final seq = editor.revealSeq;
      if (seq == lastRevealSeq) {
        return;
      }
      lastRevealSeq = seq;
      void stealAt(int depth) {
        if (depth >= 5) {
          return;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          thief.requestFocus();
          stealAt(depth + 1);
        });
      }

      stealAt(0);
    }

    editor.addListener(stealFocus);
    addTearDown(() => editor.removeListener(stealFocus));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 440,
            child: Column(
              children: [
                FindReplaceOverlay(
                  findController: findController,
                  editorController: editor,
                ),
                Focus(focusNode: thief, child: const SizedBox.shrink()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final patternField = tester
        .widget<TextField>(find.byType(TextField).first)
        .focusNode!;
    expect(
      patternField.hasFocus,
      isTrue,
      reason: 'cmd+F 后即使编辑器跨帧重试抢焦，焦点也应稳定在搜索框',
    );

    findController.next();
    await tester.pumpAndSettle();
    expect(patternField.hasFocus, isTrue, reason: '跨段跳转（多帧抢焦）后焦点仍应在搜索框');

    await tester.pumpWidget(const SizedBox.shrink());
    findController.dispose();
    editor.dispose();
  });

  testWidgets('选中文字填入后光标在搜索框末尾而非全选', (tester) async {
    final editor = LoreTextController(text: '查找内容');
    final findController = FindReplaceController()
      ..setPattern('查找')
      ..recompute(editor.text);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 440,
            child: FindReplaceOverlay(
              findController: findController,
              editorController: editor,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, '查找');
    expect(
      field.controller!.selection,
      const TextSelection.collapsed(offset: 2),
      reason: 'cmd+F 填入选中文字后光标应在末尾，便于追加而非覆盖',
    );
    expect(field.focusNode!.hasFocus, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    findController.dispose();
    editor.dispose();
  });
}
