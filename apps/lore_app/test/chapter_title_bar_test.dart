import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_app/features/workspace/chapter_title_bar.dart';
import 'package:lore_editor/lore_editor.dart';

void main() {
  testWidgets('renders locked prefix and editable subtitle', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: ChapterTitleBar(
            chapterNumber: 3,
            subtitle: '甜蜜的家',
            style: const EditorStyle.defaults(),
            onChanged: (_) {},
          ),
        ),
      ),
    );

    // 锁定前缀以只读 Text 呈现，副标题在无框 TextField 中。
    expect(find.text('第3章'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.widgetWithText(TextField, '甜蜜的家'), findsOneWidget);
  });

  testWidgets('typing in the subtitle field reports onChanged', (tester) async {
    String? reported;
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: ChapterTitleBar(
            chapterNumber: 1,
            subtitle: '',
            style: const EditorStyle.defaults(),
            onChanged: (value) => reported = value,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '开端');
    expect(reported, '开端');
  });

  testWidgets('submit action triggers onEnter', (tester) async {
    var entered = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: ChapterTitleBar(
            chapterNumber: 1,
            subtitle: 'x',
            style: const EditorStyle.defaults(),
            onChanged: (_) {},
            onEnter: () => entered += 1,
          ),
        ),
      ),
    );

    await tester.showKeyboard(find.byType(TextField));
    // done 动作 = 副标题按回车 → onEnter。
    await tester.testTextInput.receiveAction(TextInputAction.done);

    expect(entered, 1);
  });

  testWidgets('syncs subtitle from props when not focused', (tester) async {
    late StateSetter setState;
    var subtitle = '旧';
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: StatefulBuilder(
            builder: (context, s) {
              setState = s;
              return ChapterTitleBar(
                chapterNumber: 2,
                subtitle: subtitle,
                style: const EditorStyle.defaults(),
                onChanged: (_) {},
              );
            },
          ),
        ),
      ),
    );

    expect(find.widgetWithText(TextField, '旧'), findsOneWidget);
    setState(() => subtitle = '新');
    await tester.pump();
    // 未聚焦时，外部 subtitle 变化同步进字段。
    expect(find.widgetWithText(TextField, '新'), findsOneWidget);
  });
}
