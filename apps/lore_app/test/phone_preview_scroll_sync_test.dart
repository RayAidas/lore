import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_app/features/workspace/phone_preview/phone_preview_scroll_sync.dart';

/// 构造一个高 200 的滚动视图（内容高 [contentHeight]），maxScrollExtent =
/// contentHeight - 200。
Widget _scrollBox(ScrollController controller, double contentHeight) {
  return SizedBox(
    height: 200,
    child: SingleChildScrollView(
      controller: controller,
      child: SizedBox(height: contentHeight),
    ),
  );
}

void main() {
  testWidgets('源滚动按百分比驱动目标，反向亦然，且不形成回环', (tester) async {
    final source = ScrollController();
    final target = ScrollController();
    final sync = PhonePreviewScrollSync(target: target);
    addTearDown(() {
      sync.dispose();
      source.dispose();
      target.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            Expanded(child: _scrollBox(source, 1000)),
            Expanded(child: _scrollBox(target, 1000)),
          ],
        ),
      ),
    );

    sync.bind(source);
    await tester.pump(); // 触发 bind 的 post-frame 初始同步

    expect(source.position.maxScrollExtent, 800);
    expect(target.position.maxScrollExtent, 800);

    // 源滚到一半 → 目标跟随到一半。
    source.jumpTo(400);
    await tester.pump();
    expect(target.position.pixels, closeTo(400, 0.5));
    // 回环保护：源仍停在测试设定的位置，未被反向回调推走。
    expect(source.position.pixels, 400);

    // 目标滚到底 → 源跟随到底（反向）。
    target.jumpTo(800);
    await tester.pump();
    expect(source.position.pixels, closeTo(800, 0.5));
  });

  testWidgets('两侧内容高度不同时按百分比（非像素）对齐', (tester) async {
    final source = ScrollController();
    final target = ScrollController();
    final sync = PhonePreviewScrollSync(target: target);
    addTearDown(() {
      sync.dispose();
      source.dispose();
      target.dispose();
    });

    // 源内容 1000（max 800），目标内容 500（max 300）。
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            Expanded(child: _scrollBox(source, 1000)),
            Expanded(child: _scrollBox(target, 500)),
          ],
        ),
      ),
    );

    sync.bind(source);
    await tester.pump();

    // 源滚到 1/4（200/800）→ 目标应到 1/4（300/4 = 75）。
    source.jumpTo(200);
    await tester.pump();
    expect(target.position.pixels, closeTo(75, 0.5));
  });

  testWidgets('bind(null) 解绑后源滚动不再影响目标', (tester) async {
    final source = ScrollController();
    final target = ScrollController();
    final sync = PhonePreviewScrollSync(target: target);
    addTearDown(() {
      sync.dispose();
      source.dispose();
      target.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            Expanded(child: _scrollBox(source, 1000)),
            Expanded(child: _scrollBox(target, 1000)),
          ],
        ),
      ),
    );

    sync.bind(source);
    await tester.pump();
    source.jumpTo(400);
    await tester.pump();
    expect(target.position.pixels, closeTo(400, 0.5));

    // 解绑后：源继续滚，目标不再跟随（停在被重置的 0）。
    sync.bind(null);
    target.jumpTo(0);
    await tester.pump();
    source.jumpTo(800);
    await tester.pump();
    expect(target.position.pixels, 0);
  });

  testWidgets('重绑到新源后，旧源不再驱动目标、新源驱动目标', (tester) async {
    final sourceA = ScrollController();
    final sourceB = ScrollController();
    final target = ScrollController();
    final sync = PhonePreviewScrollSync(target: target);
    addTearDown(() {
      sync.dispose();
      sourceA.dispose();
      sourceB.dispose();
      target.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            Expanded(child: _scrollBox(sourceA, 1000)),
            Expanded(child: _scrollBox(sourceB, 1000)),
            Expanded(child: _scrollBox(target, 1000)),
          ],
        ),
      ),
    );

    sync.bind(sourceA);
    await tester.pump();
    sourceA.jumpTo(400);
    await tester.pump();
    expect(target.position.pixels, closeTo(400, 0.5));

    // 重绑到 B：先清掉 target，再验证 A 的监听确实被移除。
    sync.bind(sourceB);
    target.jumpTo(0);
    await tester.pump();

    sourceA.jumpTo(800);
    await tester.pump();
    expect(target.position.pixels, 0); // 旧源 A 不再驱动目标

    sourceB.jumpTo(200);
    await tester.pump();
    expect(target.position.pixels, closeTo(200, 0.5)); // 新源 B 驱动目标
  });
}
