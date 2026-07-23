import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_app/features/preferences/keybinding_recorder.dart';
import 'package:lore_domain/lore_domain.dart';

void main() {
  group('formatKeyLabel', () {
    test('uppercases letters and passes through digits and punctuation', () {
      expect(formatKeyLabel(0x73), 'S'); // a–z → 大写
      expect(formatKeyLabel(0x31), '1'); // 数字
      expect(formatKeyLabel(0x2c), ','); // 标点
      expect(formatKeyLabel(0x5c), r'\'); // 反斜杠
    });

    test(
      'maps special keys to readable symbols instead of blank control chars',
      () {
        // 这些键的 keyLabel 是原始控制字符（回车=\r），直接渲染会空白。
        expect(formatKeyLabel(LogicalKeyboardKey.enter.keyId), 'Enter');
        expect(formatKeyLabel(LogicalKeyboardKey.backspace.keyId), '⌫');
        expect(formatKeyLabel(LogicalKeyboardKey.tab.keyId), '⇥');
        expect(formatKeyLabel(LogicalKeyboardKey.space.keyId), 'Space');
        expect(formatKeyLabel(LogicalKeyboardKey.arrowUp.keyId), '↑');
      },
    );
  });

  group('KeyCombinationDisplay', () {
    testWidgets('renders all modifier caps plus the main key', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: KeyCombinationDisplay(
                combination: KeyCombination(
                  logicalKeyId: 0x73, // S
                  meta: true,
                  shift: true,
                  control: true,
                  alt: true,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('⌃'), findsOneWidget);
      expect(find.text('⌥'), findsOneWidget);
      expect(find.text('⇧'), findsOneWidget);
      expect(find.text('⌘'), findsOneWidget);
      expect(find.text('S'), findsOneWidget);
    });
  });

  group('KeybindingField', () {
    Future<void> mountField(
      WidgetTester tester, {
      required KeyCombination? combination,
      required Map<ShortcutAction, KeyCombination> allBindings,
      required ValueChanged<KeyCombination> onRecorded,
      required VoidCallback onCleared,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: KeybindingField(
                action: ShortcutAction.save,
                combination: combination,
                allBindings: allBindings,
                onRecorded: onRecorded,
                onCleared: onCleared,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('shows keycap when bound and 未设置 when unset', (tester) async {
      await mountField(
        tester,
        combination: const KeyCombination(logicalKeyId: 0x73, meta: true),
        allBindings: const {},
        onRecorded: (_) {},
        onCleared: () {},
      );
      expect(find.text('S'), findsOneWidget);
      expect(find.text('未设置'), findsNothing);

      await mountField(
        tester,
        combination: null,
        allBindings: const {},
        onRecorded: (_) {},
        onCleared: () {},
      );
      expect(find.text('未设置'), findsOneWidget);
    });

    testWidgets('tapping enters recording and Esc cancels without recording', (
      tester,
    ) async {
      KeyCombination? recorded;
      await mountField(
        tester,
        combination: const KeyCombination(logicalKeyId: 0x73, meta: true),
        allBindings: const {},
        onRecorded: (c) => recorded = c,
        onCleared: () {},
      );

      await tester.tap(find.byType(KeybindingField));
      await tester.pump();
      expect(find.text('按下快捷键…'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('按下快捷键…'), findsNothing);
      expect(recorded, isNull);
    });

    testWidgets('records a plain key with no modifiers', (tester) async {
      KeyCombination? recorded;
      await mountField(
        tester,
        combination: const KeyCombination(logicalKeyId: 0x73, meta: true),
        allBindings: const {},
        onRecorded: (c) => recorded = c,
        onCleared: () {},
      );

      await tester.tap(find.byType(KeybindingField));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pump();

      expect(recorded, isNotNull);
      expect(recorded!.logicalKeyId, LogicalKeyboardKey.keyF.keyId);
      expect(recorded!.meta, isFalse);
      expect(recorded!.shift, isFalse);
    });

    testWidgets('keeps listening when only a modifier is pressed', (
      tester,
    ) async {
      KeyCombination? recorded;
      await mountField(
        tester,
        combination: const KeyCombination(logicalKeyId: 0x73, meta: true),
        allBindings: const {},
        onRecorded: (c) => recorded = c,
        onCleared: () {},
      );

      await tester.tap(find.byType(KeybindingField));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(find.text('按下快捷键…'), findsOneWidget);
      expect(recorded, isNull);
    });

    testWidgets('flags a conflict with another action and does not record', (
      tester,
    ) async {
      KeyCombination? recorded;
      await mountField(
        tester,
        combination: const KeyCombination(logicalKeyId: 0x73, meta: true),
        // find 已绑「无修饰 F」，录制同组合即冲突。
        allBindings: const {
          ShortcutAction.find: KeyCombination(logicalKeyId: 0x66),
        },
        onRecorded: (c) => recorded = c,
        onCleared: () {},
      );

      await tester.tap(find.byType(KeybindingField));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pump();

      expect(find.text('与「查找」冲突，未保存'), findsOneWidget);
      expect(recorded, isNull);
    });

    testWidgets('clear button invokes onCleared', (tester) async {
      var cleared = false;
      await mountField(
        tester,
        combination: const KeyCombination(logicalKeyId: 0x73, meta: true),
        allBindings: const {},
        onRecorded: (_) {},
        onCleared: () => cleared = true,
      );

      await tester.tap(find.byTooltip('清除快捷键'));
      await tester.pump();

      expect(cleared, isTrue);
    });
  });
}
