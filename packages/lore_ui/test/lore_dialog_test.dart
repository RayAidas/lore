import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_ui/lore_ui.dart';

void main() {
  testWidgets('confirm dialog returns true and applies destructive color', (
    tester,
  ) async {
    late Future<bool> result;
    final theme = LoreTheme.light();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              result = showLoreConfirmDialog(
                context: context,
                title: '永久删除？',
                message: '此操作无法恢复。',
                confirmLabel: '永久删除',
                destructive: true,
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    final confirmButton = tester.widget<FilledButton>(
      find.byType(FilledButton),
    );
    expect(
      confirmButton.style?.backgroundColor?.resolve(<WidgetState>{}),
      theme.colorScheme.error,
    );

    await tester.tap(find.text('永久删除'));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
  });

  testWidgets('confirm dialog returns false when cancelled', (tester) async {
    late Future<bool> result;
    await tester.pumpWidget(
      MaterialApp(
        theme: LoreTheme.light(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              result = showLoreConfirmDialog(
                context: context,
                title: '确认？',
                message: '继续操作。',
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });

  testWidgets('confirm dialog returns false when barrier is dismissed', (
    tester,
  ) async {
    late Future<bool> result;
    await tester.pumpWidget(
      MaterialApp(
        theme: LoreTheme.light(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              result = showLoreConfirmDialog(
                context: context,
                title: '确认？',
                message: '继续操作。',
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });

  testWidgets('confirm dialog can disable confirmation', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: LoreTheme.light(),
        home: const Scaffold(
          body: LoreConfirmDialog(
            title: '无法删除',
            message: '请从结构面板删除。',
            confirmEnabled: false,
          ),
        ),
      ),
    );

    final confirmButton = tester.widget<FilledButton>(
      find.byType(FilledButton),
    );
    expect(confirmButton.onPressed, isNull);
  });

  testWidgets('text prompt exposes field options and returns input', (
    tester,
  ) async {
    late Future<String?> result;
    await tester.pumpWidget(
      MaterialApp(
        theme: LoreTheme.light(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              result = showLoreTextPromptDialog(
                context: context,
                title: '每日字数目标',
                label: '字数',
                initialValue: '1000',
                helperText: '留空表示不设置',
                suffixText: ' 字',
                keyboardType: TextInputType.number,
                confirmLabel: '保存',
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, '1000');
    expect(field.keyboardType, TextInputType.number);
    expect(field.decoration?.helperText, '留空表示不设置');
    expect(field.decoration?.suffixText, ' 字');
    expect(find.text('保存'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '1500');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(await result, '1500');
  });

  testWidgets('text prompt returns null when cancelled', (tester) async {
    late Future<String?> result;
    await tester.pumpWidget(
      MaterialApp(
        theme: LoreTheme.light(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              result = showLoreTextPromptDialog(
                context: context,
                title: '重命名',
                label: '新名称',
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await result, isNull);
  });

  testWidgets('actions lay out side by side, not stacked', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: LoreTheme.light(),
        home: const Scaffold(
          body: LoreConfirmDialog(
            title: '删除？',
            message: '将移到回收站。',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final confirm = tester.getRect(find.byType(FilledButton));
    final cancel = tester.getRect(find.byType(TextButton));

    // 横排：两按钮垂直中心在同一行，取消按钮在确认按钮左侧。
    // 若 minimumSize 误用 Size.fromHeight 导致按钮无限宽，会退化为上下纵排。
    expect(confirm.center.dy, closeTo(cancel.center.dy, 1));
    expect(cancel.right, lessThanOrEqualTo(confirm.left));
  });
}
