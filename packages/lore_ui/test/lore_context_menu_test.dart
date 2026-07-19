import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_ui/lore_ui.dart';

/// 测试骨架：一个按钮，点击后用 [showLoreContextMenu] 在 [position] 弹菜单。
Widget _harness({
  required List<LoreContextMenuItem> items,
  Offset position = const Offset(100, 100),
}) {
  return MaterialApp(
    theme: LoreTheme.light(),
    home: Scaffold(
      body: Center(
        child: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showLoreContextMenu(
              context: context,
              position: position,
              items: items,
            ),
            child: const Text('trigger'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders every item label', (tester) async {
    await tester.pumpWidget(
      _harness(
        items: [
          LoreContextMenuItem(label: '新建卷', onTap: () {}),
          LoreContextMenuItem(label: '重命名', onTap: () {}),
          LoreContextMenuItem(label: '移到回收站', onTap: () {}, destructive: true),
        ],
      ),
    );
    await tester.tap(find.text('trigger'));
    await tester.pump();

    expect(find.text('新建卷'), findsOneWidget);
    expect(find.text('重命名'), findsOneWidget);
    expect(find.text('移到回收站'), findsOneWidget);
  });

  testWidgets('tapping an item invokes onTap and dismisses the menu', (
    tester,
  ) async {
    var invoked = false;
    await tester.pumpWidget(
      _harness(
        items: [LoreContextMenuItem(label: '重命名', onTap: () => invoked = true)],
      ),
    );
    await tester.tap(find.text('trigger'));
    await tester.pump();

    await tester.tap(find.text('重命名'));
    await tester.pump();

    expect(invoked, isTrue);
    expect(find.text('重命名'), findsNothing);
  });

  testWidgets('tapping outside dismisses the menu without invoking onTap', (
    tester,
  ) async {
    var invoked = false;
    await tester.pumpWidget(
      _harness(
        items: [LoreContextMenuItem(label: '重命名', onTap: () => invoked = true)],
      ),
    );
    await tester.tap(find.text('trigger'));
    await tester.pump();

    // 菜单定位在 (100,100)；点左上角空白处，落点在卡片之外。
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();

    expect(invoked, isFalse);
    expect(find.text('重命名'), findsNothing);
  });

  testWidgets('a disabled item does not invoke onTap nor close the menu', (
    tester,
  ) async {
    var invoked = false;
    await tester.pumpWidget(
      _harness(
        items: [
          LoreContextMenuItem(
            label: '关闭其他',
            onTap: () => invoked = true,
            enabled: false,
          ),
        ],
      ),
    );
    await tester.tap(find.text('trigger'));
    await tester.pump();

    await tester.tap(find.text('关闭其他'));
    await tester.pumpAndSettle();

    expect(invoked, isFalse);
    expect(find.text('关闭其他'), findsOneWidget);
  });

  testWidgets('showing again at a new position replaces the previous menu', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        items: [LoreContextMenuItem(label: '第一项', onTap: () {})],
      ),
    );
    await tester.tap(find.text('trigger'));
    await tester.pump();
    expect(find.text('第一项'), findsOneWidget);

    // 再次弹出不同条目：旧菜单应被替换，全局仅保留新菜单。
    showLoreContextMenu(
      context: tester.element(find.text('trigger')),
      position: const Offset(50, 50),
      items: [LoreContextMenuItem(label: '第二项', onTap: () {})],
    );
    await tester.pump();

    expect(find.text('第一项'), findsNothing);
    expect(find.text('第二项'), findsOneWidget);
  });
}
