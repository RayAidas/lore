import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_ui/lore_ui.dart';

void main() {
  testWidgets('renders as centered dialog on wide screens', (tester) async {
    // flutter_test 默认视口 800x600 ≥ 600 断点，走居中 Dialog 分支。
    late Future<void> result;
    await tester.pumpWidget(
      MaterialApp(
        theme: LoreTheme.light(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              result = showLorePanelSheet(
                context: context,
                title: '设置',
                icon: Icons.settings_outlined,
                child: const Text('面板内容'),
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    // 刻意不用 Dialog widget（避开 Material 3 的隐藏 maxWidth），改用 Center
    // 自承载，因此这里只验证面板内容已渲染。
    expect(find.text('设置'), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    expect(find.text('面板内容'), findsOneWidget);
    // 标题栏自带关闭按钮。
    expect(find.byTooltip('关闭'), findsOneWidget);

    // 关闭按钮点击后面板消失、Future 完成。
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(result, completes);
  });

  testWidgets('renders as bottom sheet on narrow screens', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: LoreTheme.light(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showLorePanelSheet(
              context: context,
              title: '回收站',
              child: const Text('面板内容'),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    // 窄屏走 showModalBottomSheet，内部会挂载 BottomSheet。
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('回收站'), findsOneWidget);
    expect(find.text('面板内容'), findsOneWidget);
  });

  testWidgets('dismissing the barrier closes the dialog', (tester) async {
    late Future<void> result;
    await tester.pumpWidget(
      MaterialApp(
        theme: LoreTheme.light(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              result = showLorePanelSheet(
                context: context,
                title: '设置',
                child: const SizedBox(height: 20),
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    // 点击左上角遮罩区域（Dialog 居中于 800x600 视口，左上角属于遮罩）。
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    // 关闭后面板消失（不再用 Dialog 类型判断，改查关闭按钮）。
    expect(find.byTooltip('关闭'), findsNothing);
    expect(result, completes);
  });

  testWidgets('desktop panel fills its maxWidth instead of shrinking', (
    tester,
  ) async {
    // 回归守卫：Dialog 给的是 loose 约束，Column(mainAxisSize.min) 会把面板
    // shrink-wrap 成过窄的一列（内容自适应 → 宽度 < maxWidth → 两列布局不触发）。
    // 固定宽度 + crossAxisAlignment.stretch 后，内容应吃满 maxWidth。
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showLorePanelSheet(
              context: context,
              title: '面板',
              maxWidth: 760,
              child: const SizedBox(key: ValueKey('probe'), height: 100),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    final probeWidth = tester
        .getRect(find.byKey(const ValueKey('probe')))
        .width;
    // 内容区 = 面板宽(760) 减去左右 1px 边框 ≈ 758。若 shrink-wrap 回归，
    // probe 宽会远小于此（SizedBox 无 width 在 loose 下为 0）。
    expect(probeWidth, closeTo(760, 3));
  });

  testWidgets('panel provides a Material ancestor for material children', (
    tester,
  ) async {
    // 回归：去 Dialog widget 后曾丢失 Material 祖先，导致 DropdownButton/Switch/
    // Slider 抛 "No Material widget found"。用 DropdownButton 作为 child 守护。
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showLorePanelSheet(
              context: context,
              title: '面板',
              child: DropdownButton<String>(
                value: 'a',
                items: const [DropdownMenuItem(value: 'a', child: Text('a'))],
                onChanged: (_) {},
              ),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    // 若丢失 Material 祖先，pumpAndSettle 会抛 "No Material widget found"。
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButton<String>), findsOneWidget);
  });
}
