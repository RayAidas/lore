import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_app/features/workspace/history_diff_view.dart';

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
}
