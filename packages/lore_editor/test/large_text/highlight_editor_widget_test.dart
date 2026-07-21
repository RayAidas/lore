import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
}
