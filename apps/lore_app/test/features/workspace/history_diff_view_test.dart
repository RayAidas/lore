import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_app/features/workspace/history_diff_mode.dart';
import 'package:lore_app/features/workspace/history_diff_view.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_editor/lore_editor.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('相同文本摘要为 +0 / −0', (tester) async {
    await tester.pumpWidget(
      wrap(const HistoryDiffView(oldText: '雨夜倾盆而下', newText: '雨夜倾盆而下')),
    );
    await tester.pump();
    expect(find.text('+0'), findsOneWidget);
    expect(find.text('−0'), findsOneWidget);
  });

  testWidgets('纯新增产生正的增计摘要', (tester) async {
    await tester.pumpWidget(
      wrap(const HistoryDiffView(oldText: '原文', newText: '原文加了一句话')),
    );
    await tester.pump();
    expect(find.text('+5'), findsOneWidget);
    expect(find.text('−0'), findsOneWidget);
  });

  testWidgets('纯删除产生正的删计摘要', (tester) async {
    await tester.pumpWidget(
      wrap(const HistoryDiffView(oldText: '原文删掉几个字', newText: '原文')),
    );
    await tester.pump();
    expect(find.text('+0'), findsOneWidget);
    expect(find.text('−5'), findsOneWidget);
  });

  testWidgets('复用 State 切换版本时重算 diff（不卡在第一个版本）', (tester) async {
    // 模拟点版本 A：
    await tester.pumpWidget(
      wrap(const HistoryDiffView(oldText: '原文', newText: '原文')),
    );
    await tester.pump();
    expect(find.text('+0'), findsOneWidget);
    // 模拟点版本 B：同一实例换 newText → State 复用，须走 didUpdateWidget 重算。
    await tester.pumpWidget(
      wrap(const HistoryDiffView(oldText: '原文', newText: '原文加了一句话')),
    );
    await tester.pump();
    expect(find.text('+5'), findsOneWidget);
    expect(find.text('−0'), findsOneWidget);
  });

  testWidgets('窄屏渲染 unified，宽屏渲染并排双栏', (tester) async {
    // 窄屏：单栏 SelectableText。
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      wrap(const HistoryDiffView(oldText: '旧', newText: '新')),
    );
    await tester.pump();
    expect(find.byType(SelectableText), findsOneWidget);
  });

  testWidgets('多段文本按段落切块渲染（每段一个 SelectableText）', (tester) async {
    await tester.pumpWidget(
      wrap(const HistoryDiffView(oldText: '第一段\n第二段', newText: '第一段\n第二段')),
    );
    await tester.pump();
    // 两段（中间一个 \n）→ 两个段落块，各一个 SelectableText。
    expect(find.byType(SelectableText), findsNWidgets(2));
  });

  testWidgets('段间空行保留为独立空段（不与相邻段合并）', (tester) async {
    await tester.pumpWidget(
      wrap(const HistoryDiffView(oldText: '第一段\n\n第三段', newText: '第一段\n\n第三段')),
    );
    await tester.pump();
    // 首尾两段为 SelectableText，中间空行渲染为占高空白（非 SelectableText）。
    expect(find.byType(SelectableText), findsNWidgets(2));
  });

  testWidgets('新增空行变化渲染为着色空行（可见）', (tester) async {
    await tester.pumpWidget(
      wrap(const HistoryDiffView(oldText: '第一段\n第三段', newText: '第一段\n\n第三段')),
    );
    await tester.pump();
    // 新增的空行整行着色 → diff 视图内出现一个 ColoredBox（绿底）。
    final tinted = find.descendant(
      of: find.byType(HistoryDiffView),
      matching: find.byType(ColoredBox),
    );
    expect(tinted, findsOneWidget);
    expect(
      tester.widget<ColoredBox>(tinted).color,
      const Color(0xFF1B7F3A).withValues(alpha: 0.16),
    );
  });

  testWidgets('删除空行变化渲染为着色空行（红底）', (tester) async {
    await tester.pumpWidget(
      wrap(const HistoryDiffView(oldText: '第一段\n\n第三段', newText: '第一段\n第三段')),
    );
    await tester.pump();
    final tinted = find.descendant(
      of: find.byType(HistoryDiffView),
      matching: find.byType(ColoredBox),
    );
    expect(tinted, findsOneWidget);
    expect(
      tester.widget<ColoredBox>(tinted).color,
      const Color(0xFFC2364B).withValues(alpha: 0.16),
    );
  });

  testWidgets('未变化的空行不着色', (tester) async {
    await tester.pumpWidget(
      wrap(const HistoryDiffView(oldText: '第一段\n\n第三段', newText: '第一段\n\n第三段')),
    );
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(HistoryDiffView),
        matching: find.byType(ColoredBox),
      ),
      findsNothing,
    );
  });

  testWidgets('仅含空白字符的空行（首行缩进 　　 ）变化也整行着色', (tester) async {
    await tester.pumpWidget(
      wrap(const HistoryDiffView(oldText: '第一段\n第三段', newText: '第一段\n　　\n第三段')),
    );
    await tester.pump();
    final tinted = find.descendant(
      of: find.byType(HistoryDiffView),
      matching: find.byType(ColoredBox),
    );
    expect(tinted, findsOneWidget);
    expect(
      tester.widget<ColoredBox>(tinted).color,
      const Color(0xFF1B7F3A).withValues(alpha: 0.16),
    );
  });

  testWidgets('删除仅含空白字符的空行也整行着色（红底）', (tester) async {
    await tester.pumpWidget(
      wrap(const HistoryDiffView(oldText: '第一段\n　　\n第三段', newText: '第一段\n第三段')),
    );
    await tester.pump();
    final tinted = find.descendant(
      of: find.byType(HistoryDiffView),
      matching: find.byType(ColoredBox),
    );
    expect(tinted, findsOneWidget);
    expect(
      tester.widget<ColoredBox>(tinted).color,
      const Color(0xFFC2364B).withValues(alpha: 0.16),
    );
  });

  testWidgets('未变化的含空白空行不着色', (tester) async {
    await tester.pumpWidget(
      wrap(
        const HistoryDiffView(oldText: '第一段\n　　\n第三段', newText: '第一段\n　　\n第三段'),
      ),
    );
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(HistoryDiffView),
        matching: find.byType(ColoredBox),
      ),
      findsNothing,
    );
  });

  testWidgets('关闭首行缩进时段首不带全角空格', (tester) async {
    await tester.pumpWidget(
      wrap(
        HistoryDiffView(
          oldText: '正文',
          newText: '正文',
          style: const EditorStyle.defaults().copyWith(firstLineIndent: false),
        ),
      ),
    );
    await tester.pump();
    final rich = tester.widget<SelectableText>(find.byType(SelectableText));
    final span = rich.textSpan as TextSpan;
    // 无缩进：首个子 span 直接是正文（不以全角空格开头）。
    final first = (span.children?.first as TextSpan?)?.text ?? '';
    expect(first.startsWith(paragraphIndent), isFalse);
  });

  testWidgets('章节标题作为独立首块渲染（标题不变→中性单行）', (tester) async {
    await tester.pumpWidget(
      wrap(
        const HistoryDiffView(
          oldText: '正文',
          newText: '正文',
          oldTitle: '第1章 起',
          newTitle: '第1章 起',
        ),
      ),
    );
    await tester.pump();
    // 标题块 + 正文块 = 两个 SelectableText。
    expect(find.byType(SelectableText), findsNWidgets(2));
    // 正文未变 → 摘要仍为 +0 / −0（标题不计入正文增删）。
    expect(find.text('+0'), findsOneWidget);
    expect(find.text('−0'), findsOneWidget);
  });

  testWidgets('标题变更在 unified 下做字符级 diff（红删绿增）', (tester) async {
    await tester.pumpWidget(
      wrap(
        const HistoryDiffView(
          oldText: '正文',
          newText: '正文',
          oldTitle: '第1章 起',
          newTitle: '第1章 结',
        ),
      ),
    );
    await tester.pump();
    // 标题块（含 diff）+ 正文块。
    final texts = tester.widgetList<SelectableText>(
      find.byType(SelectableText),
    );
    final titleSpan = texts.first.textSpan as TextSpan;
    // 标题块内能找到被删的「起」与新增的「结」。
    final flat = _flatten(titleSpan);
    expect(flat, contains('起'));
    expect(flat, contains('结'));
  });

  testWidgets('正文增删着色走 TextAnnotation 管线（删除红底删除线、新增绿底）', (tester) async {
    await tester.pumpWidget(
      wrap(const HistoryDiffView(oldText: 'abc', newText: 'axc')),
    );
    await tester.pump();
    // 无标题 → 仅 1 个正文段落 SelectableText。
    final body = tester.widget<SelectableText>(find.byType(SelectableText));
    final children = (body.textSpan as TextSpan).children!;
    final del =
        children.firstWhere((s) => (s as TextSpan).text == 'b') as TextSpan;
    final ins =
        children.firstWhere((s) => (s as TextSpan).text == 'x') as TextSpan;
    // 删除：删除线 + 字形色 + 背景色。
    expect(del.style?.decoration, TextDecoration.lineThrough);
    expect(del.style?.color, isNotNull);
    expect(del.style?.backgroundColor, isNotNull);
    // 新增：字形色 + 背景色、无删除线。
    expect(ins.style?.color, isNotNull);
    expect(ins.style?.backgroundColor, isNotNull);
    expect(ins.style?.decoration ?? TextDecoration.none, TextDecoration.none);
  });

  testWidgets('内容套用 EditorTypography.contentFrame（居中 contentWidth）', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(const HistoryDiffView(oldText: '正文', newText: '正文')),
    );
    await tester.pump();
    final boxes = tester.widgetList<ConstrainedBox>(
      find.byType(ConstrainedBox),
    );
    expect(
      boxes.any(
        (b) =>
            b.constraints.maxWidth == const EditorStyle.defaults().contentWidth,
      ),
      isTrue,
    );
  });

  testWidgets('不复读正文已有缩进（编辑器已把缩进写入文本，避免双缩进 4 字）', (tester) async {
    await tester.pumpWidget(
      wrap(const HistoryDiffView(oldText: '　　第一段', newText: '　　第一段')),
    );
    await tester.pump();
    final rich = tester.widget<SelectableText>(find.byType(SelectableText));
    // 渲染文本 == 原文（不再额外补段首缩进）。
    expect(_flatten(rich.textSpan as TextSpan), '　　第一段');
  });

  testWidgets('开启网格线时按段落渲染 TextGridLinePainter', (tester) async {
    await tester.pumpWidget(
      wrap(
        HistoryDiffView(
          oldText: '正文',
          newText: '正文',
          style: const EditorStyle.defaults().copyWith(
            gridLineMode: GridLineMode.solid,
          ),
        ),
      ),
    );
    await tester.pump();
    final painters = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
    expect(painters.any((c) => c.painter is TextGridLinePainter), isTrue);
  });

  testWidgets('默认无网格线时不渲染 TextGridLinePainter', (tester) async {
    await tester.pumpWidget(
      wrap(const HistoryDiffView(oldText: '正文', newText: '正文')),
    );
    await tester.pump();
    final painters = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
    expect(painters.any((c) => c.painter is TextGridLinePainter), isFalse);
  });

  testWidgets('网格线 drawTopLine：首段 false、其后 true（段间距上下都有线）', (tester) async {
    await tester.pumpWidget(
      wrap(
        HistoryDiffView(
          oldText: '第一段\n第二段',
          newText: '第一段\n第二段',
          style: const EditorStyle.defaults().copyWith(
            gridLineMode: GridLineMode.solid,
          ),
        ),
      ),
    );
    await tester.pump();
    final painters = tester.widgetList<CustomPaint>(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is TextGridLinePainter,
      ),
    );
    expect(painters.length, 2);
    expect(
      (painters.first.painter as TextGridLinePainter).drawTopLine,
      isFalse,
    );
    expect((painters.last.painter as TextGridLinePainter).drawTopLine, isTrue);
  });

  testWidgets('并排模式：左栏渲染删除（删除线）、右栏渲染新增（绿底）', (tester) async {
    // 宽屏（>=640）触发 split 双栏。
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      wrap(
        const HistoryDiffView(
          oldText: 'abc',
          newText: 'axc',
          mode: DiffViewMode.split,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final texts = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .toList();
    expect(texts.length, 2);
    // 树序：左栏（旧）= EQUAL+DELETE → 'abc'，'b' 带删除线。
    expect(_flatten(texts.first.textSpan as TextSpan), 'abc');
    final bSpan =
        (texts.first.textSpan as TextSpan).children!.firstWhere(
              (s) => (s as TextSpan).text == 'b',
            )
            as TextSpan;
    expect(bSpan.style?.decoration, TextDecoration.lineThrough);
    // 右栏（新）= EQUAL+INSERT → 'axc'，'x' 带背景色、无删除线。
    expect(_flatten(texts.last.textSpan as TextSpan), 'axc');
    final xSpan =
        (texts.last.textSpan as TextSpan).children!.firstWhere(
              (s) => (s as TextSpan).text == 'x',
            )
            as TextSpan;
    expect(xSpan.style?.backgroundColor, isNotNull);
    expect(xSpan.style?.decoration ?? TextDecoration.none, TextDecoration.none);
  });
}

String _flatten(TextSpan span) {
  final buffer = StringBuffer();
  void walk(TextSpan s) {
    if (s.text != null) buffer.write(s.text);
    for (final child in s.children ?? const <InlineSpan>[]) {
      if (child is TextSpan) walk(child);
    }
  }

  walk(span);
  return buffer.toString();
}
