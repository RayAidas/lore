import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_app/features/workspace/phone_preview/phone_preview_page_sync.dart';

Widget _sourceBox(ScrollController c) => SizedBox(
  height: 200,
  child: SingleChildScrollView(
    controller: c,
    child: const SizedBox(height: 1000),
  ),
);

void main() {
  testWidgets('编辑器滚动百分比映射到页号（单向）', (tester) async {
    final source = ScrollController();
    final page = PageController();
    final sync = PhonePreviewPageSync(target: page, pageCount: () => 5);
    addTearDown(() {
      sync.dispose();
      source.dispose();
      page.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 600,
            height: 200,
            child: Row(
              children: [
                Expanded(child: _sourceBox(source)),
                SizedBox(
                  width: 200,
                  height: 200,
                  child: PageView(
                    controller: page,
                    children: [
                      for (var i = 0; i < 5; i++) Center(child: Text('$i')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    sync.bind(source);
    await tester.pumpAndSettle();
    expect(source.position.maxScrollExtent, 800); // 1000 - 200

    // 1/2 (400/800) → round(0.5 × 4) = 第 2 页。
    source.jumpTo(400);
    await tester.pump();
    expect(page.page, 2);
    // 顶部 → 第 0 页。
    source.jumpTo(0);
    await tester.pump();
    expect(page.page, 0);
    // 底部 → 末页。
    source.jumpTo(800);
    await tester.pump();
    expect(page.page, 4);
  });

  testWidgets('pageCount <= 1 时不翻页', (tester) async {
    final source = ScrollController();
    final page = PageController();
    final sync = PhonePreviewPageSync(target: page, pageCount: () => 1);
    addTearDown(() {
      sync.dispose();
      source.dispose();
      page.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 600,
            height: 200,
            child: Row(
              children: [
                Expanded(child: _sourceBox(source)),
                SizedBox(
                  width: 200,
                  height: 200,
                  child: PageView(
                    controller: page,
                    children: const [Center(child: Text('only'))],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    sync.bind(source);
    await tester.pumpAndSettle();
    source.jumpTo(400);
    await tester.pump();
    expect(page.page, 0); // 单页不动
  });
}
