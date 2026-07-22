import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_editor/lore_editor.dart';

/// 模拟鼠标右键(fluent_test 的 startGesture 不支持 button 参数,
/// 直接向 GestureBinding 发带 secondary buttons 的 PointerEvent)。
void _secondaryTap(Offset location) {
  final binding = GestureBinding.instance;
  binding.handlePointerEvent(
    PointerDownEvent(position: location, buttons: kSecondaryMouseButton),
  );
  binding.handlePointerEvent(
    PointerUpEvent(position: location, buttons: kSecondaryMouseButton),
  );
}

void main() {
  testWidgets('右键触发 onContextMenu,渲染高亮时不崩溃', (tester) async {
    final controller = LoreLargeTextController(text: '这是一段高亮文字的正文内容。');
    final scrollController = ScrollController();
    controller.setHighlights([
      Highlight(
        id: 'h1',
        start: 4,
        end: 8,
        colorArgb: 0xFFFFD54F,
        anchorText: '高亮文字',
      ),
    ]);
    Offset? menuPosition;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoreLargeTextEditor(
            controller: controller,
            scrollController: scrollController,
            onContextMenu: (pos) => menuPosition = pos,
          ),
        ),
      ),
    );

    // 高亮存在时正常渲染(说明 _BlockHighlightPainter 接入、
    // _localHighlightsForBlock 跨段求交未崩)。
    expect(find.byType(LoreLargeTextEditor), findsOneWidget);

    // 右键应触发 onContextMenu。
    final center = tester.getCenter(find.byType(LoreLargeTextEditor));
    _secondaryTap(center);
    await tester.pumpAndSettle();
    expect(menuPosition, isNotNull);

    scrollController.dispose();
    controller.dispose();
  });

  testWidgets('查找中文匹配由 EditableText span 精确高亮', (tester) async {
    const text =
        '　　“我应该已经死了，那……这里是阴曹地府？”纪宁凭空出现，不由好奇观察着陌生环境，便听到那王爷的叫嚣，这让纪宁更生疑惑。';
    final controller = LoreLargeTextController(text: text);
    final scrollController = ScrollController();
    controller.setFindMatches(
      SearchQuery(
        pattern: '纪宁',
        caseSensitive: false,
        useRegex: false,
      ).findAllIn(text),
      currentIndex: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoreLargeTextEditor(
            controller: controller,
            scrollController: scrollController,
          ),
        ),
      ),
    );

    final editable = tester.widget<EditableText>(find.byType(EditableText));
    final span = editable.controller.buildTextSpan(
      context: tester.element(find.byType(EditableText)),
      style: editable.style,
      withComposing: true,
    );
    final highlighted = span.children!
        .whereType<TextSpan>()
        .where((child) => child.style?.backgroundColor != null)
        .map((child) => child.text)
        .toList();
    expect(highlighted, ['纪宁', '纪宁']);

    scrollController.dispose();
    controller.dispose();
  });

  testWidgets('onContextMenu 为 null 时右键不抛错', (tester) async {
    final controller = LoreLargeTextController(text: '短文本');
    final scrollController = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoreLargeTextEditor(
            controller: controller,
            scrollController: scrollController,
          ),
        ),
      ),
    );
    final center = tester.getCenter(find.byType(LoreLargeTextEditor));
    _secondaryTap(center);
    await tester.pumpAndSettle();
    // 到此未抛异常即通过。
    expect(find.byType(LoreLargeTextEditor), findsOneWidget);
    scrollController.dispose();
    controller.dispose();
  });

  testWidgets('触摸长按 500ms 触发 onContextMenu,移动取消', (tester) async {
    final controller = LoreLargeTextController(text: '触摸长按测试文本内容');
    final scrollController = ScrollController();
    Offset? menuPosition;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoreLargeTextEditor(
            controller: controller,
            scrollController: scrollController,
            onContextMenu: (pos) => menuPosition = pos,
          ),
        ),
      ),
    );
    final center = tester.getCenter(find.byType(LoreLargeTextEditor));
    const kind = PointerDeviceKind.touch;
    const buttons = kPrimaryMouseButton;
    // 长按未到 500ms → 不触发。
    GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(position: center, kind: kind, buttons: buttons),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(menuPosition, isNull);
    // 移动超 touchSlop → 取消长按(转为拖选)。
    GestureBinding.instance.handlePointerEvent(
      PointerMoveEvent(
        position: Offset(center.dx + 50, center.dy),
        kind: kind,
        buttons: buttons,
      ),
    );
    await tester.pump(const Duration(milliseconds: 400)); // 累计 700ms 但已取消
    expect(menuPosition, isNull);
    GestureBinding.instance.handlePointerEvent(
      PointerUpEvent(position: center, kind: kind, buttons: buttons),
    );
    // 第二次:不动,长按到 500ms → 触发。
    GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(position: center, kind: kind, buttons: buttons),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(menuPosition, isNotNull);
    GestureBinding.instance.handlePointerEvent(
      PointerUpEvent(position: center, kind: kind, buttons: buttons),
    );
    scrollController.dispose();
    controller.dispose();
  });
}
