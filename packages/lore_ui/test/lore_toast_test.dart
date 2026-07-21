import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_ui/lore_ui.dart';

void main() {
  /// 默认停留时长。必须 > 入场动画（200ms）——见 [enter]，入场所推进的时间
  /// 要短于本值，避免 pumpAndSettle 一路推进到计时器触发、toast 提前消失。
  const kDuration = Duration(milliseconds: 500);

  /// 入场推进：先 pump 一帧让 OverlayEntry mount（启动入场动画与计时器），
  /// 再推进到落位。长于 200ms 入场动画、短于 [kDuration]，保证计时器未触发。
  /// 注意不能用 pumpAndSettle——它会一路推进到 duration 之后让 toast 提前消失。
  Future<void> enter(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  /// 推进到 duration 之后并跑完退场动画，让 toast 自然移除并消费计时器。
  Future<void> drainAndSettle(WidgetTester tester) async {
    await tester.pump(kDuration + const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
  }

  /// 用 trigger 按钮承载 toast 的 context（Scaffold 之下、根 Overlay 可达）。
  Future<void> pumpApp(
    WidgetTester tester, {
    required void Function(BuildContext context) onTrigger,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => onTrigger(context),
                child: const Text('trigger'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('show displays the message', (tester) async {
    await pumpApp(
      tester,
      onTrigger: (context) => LoreToast.show(
        context,
        message: '已复制路径',
        type: LoreToastType.success,
        duration: kDuration,
      ),
    );

    await tester.tap(find.text('trigger'));
    await enter(tester);
    expect(find.text('已复制路径'), findsOneWidget);

    await drainAndSettle(tester);
    expect(find.text('已复制路径'), findsNothing);
  });

  testWidgets('toast auto-dismisses after its duration', (tester) async {
    await pumpApp(
      tester,
      onTrigger: (context) => LoreToast.show(
        context,
        message: '稍纵即逝',
        type: LoreToastType.info,
        duration: kDuration,
      ),
    );

    await tester.tap(find.text('trigger'));
    await enter(tester);
    expect(find.text('稍纵即逝'), findsOneWidget);

    await drainAndSettle(tester);
    expect(find.text('稍纵即逝'), findsNothing);
  });

  testWidgets('a new toast replaces the previous one', (tester) async {
    var taps = 0;
    await pumpApp(
      tester,
      onTrigger: (context) {
        taps += 1;
        LoreToast.show(
          context,
          message: 'toast $taps',
          type: LoreToastType.success,
          duration: kDuration,
        );
      },
    );

    await tester.tap(find.text('trigger'));
    await enter(tester);
    expect(find.text('toast 1'), findsOneWidget);

    await tester.tap(find.text('trigger'));
    await enter(tester);
    expect(find.text('toast 1'), findsNothing);
    expect(find.text('toast 2'), findsOneWidget);

    await drainAndSettle(tester);
  });

  testWidgets('tap dismisses the toast early', (tester) async {
    await pumpApp(
      tester,
      onTrigger: (context) => LoreToast.show(
        context,
        message: '点我关闭',
        type: LoreToastType.warning,
        duration: const Duration(seconds: 30),
      ),
    );

    await tester.tap(find.text('trigger'));
    await enter(tester); // toast 落位到可命中位置
    expect(find.text('点我关闭'), findsOneWidget);

    await tester.tap(find.text('点我关闭')); // 点击 toast 本体提前关闭
    await tester.pumpAndSettle(); // 退场动画 + remove
    expect(find.text('点我关闭'), findsNothing);

    // 消费仍 pending 的 30s 计时器（回调时 toast 已移除，no-op）。
    await tester.pump(const Duration(seconds: 31));
  });

  testWidgets('renders the matching icon for each type', (tester) async {
    final cases = <(LoreToastType, IconData)>[
      (LoreToastType.success, Icons.check_circle_rounded),
      (LoreToastType.info, Icons.info_outline_rounded),
      (LoreToastType.warning, Icons.warning_amber_rounded),
      (LoreToastType.error, Icons.error_outline_rounded),
    ];

    for (final (type, icon) in cases) {
      await pumpApp(
        tester,
        onTrigger: (context) => LoreToast.show(
          context,
          message: 'msg-$type',
          type: type,
          duration: kDuration,
        ),
      );

      await tester.tap(find.text('trigger'));
      await enter(tester);
      expect(find.byIcon(icon), findsOneWidget);

      await drainAndSettle(tester);
    }
  });

  testWidgets('show throws when no Overlay ancestor exists', (tester) async {
    // 无 MaterialApp → 无 Overlay。锁定 show 的失败契约：调用方必须在
    // MaterialApp 之下调用，否则显式失败而非静默。
    await tester.pumpWidget(const SizedBox.shrink());
    expect(
      () => LoreToast.show(
        tester.element(find.byType(SizedBox)),
        message: 'no overlay',
      ),
      throwsA(isA<Error>()),
    );
  });
}
