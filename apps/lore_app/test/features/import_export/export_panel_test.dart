import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_app/features/import_export/export_panel.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';

import '_test_harness.dart';

void main() {
  // 共享：带一个章节的快照 + 章节正文。export panel 默认全选，导出按钮可用。
  NovelSnapshot buildSnapshot() => oneChapterNovelSnapshot();

  Future<Map<String, String>> chapterTexts(NovelSnapshot snapshot) async {
    final chapter = snapshot.contentTree.nodes.singleWhere(
      (n) => n.type == ContentNodeType.chapter,
    );
    return {absoluteChapterPath(snapshot, chapter): '第1章\n正文段落'};
  }

  testWidgets('export returns silently when save dialog is cancelled', (
    tester,
  ) async {
    final snapshot = buildSnapshot();
    final texts = await chapterTexts(snapshot);
    final harness = await ImportExportTestHarness.withNovel(
      snapshot,
      chapterTexts: texts,
    );
    addTearDown(harness.dispose);
    final fake = FakeFilePickerPlatform(); // saveFilePath stays null.
    installFakeFilePicker(fake);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportPanel(
            controller: harness.controller,
            snapshot: snapshot,
            restrictVolumeId: null,
            revealInFinder: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('导出'));
    // 取消路径不弹 SnackBar，但 _exporting 状态切换可能调度一帧定时器；
    // 用 pump 推进即可，避免 pumpAndSettle 卡在其它测试用例的副作用上。
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(fake.saveFileCalls, 1);
    // 即使取消，组好的正文仍以 bytes 形式传入 saveFile（先组后弹）。
    expect(fake.lastSaveBytes, isNotNull);
    expect(fake.lastSaveText, contains('正文段落'));
    // 取消时不弹成功 SnackBar。
    expect(find.textContaining('已导出'), findsNothing);
  });

  testWidgets('export shows success snackbar and bytes contain chapter text', (
    tester,
  ) async {
    final snapshot = buildSnapshot();
    final texts = await chapterTexts(snapshot);
    final harness = await ImportExportTestHarness.withNovel(
      snapshot,
      chapterTexts: texts,
    );
    addTearDown(harness.dispose);
    final fake = FakeFilePickerPlatform()..saveFilePath = '/tmp/out.txt';
    installFakeFilePicker(fake);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExportPanel(
            controller: harness.controller,
            snapshot: snapshot,
            restrictVolumeId: null,
            revealInFinder: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('导出'));
    // 用固定 pump 推进，避免 pumpAndSettle 被 SnackBar/Process.run 的长时
    // 计时器卡住：导出面板的 maybePop + SnackBar(showSnackBar 4s) + macOS
    // 上的 `open -R` 都会调度定时器，pumpAndSettle 难以收敛。
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(fake.saveFileCalls, 1);
    expect(fake.saveFilePath, '/tmp/out.txt');
    // 传入 saveFile 的 bytes 解码回字符串包含章节正文。
    expect(fake.lastSaveBytes, isNotNull);
    expect(fake.lastSaveText, contains('正文段落'));
    // 成功提示出现。
    expect(find.textContaining('已导出'), findsOneWidget);
  });

  testWidgets(
    'export with only empty-body chapters reports unsupportedFormat',
    (tester) async {
      final snapshot = buildSnapshot();
      // 正文为空 + 关闭「包含章节标题」：composer 既无标题也无正文 → 返回空串，
      // 面板提示 unsupportedFormat 且不调 saveFile。
      final chapter = snapshot.contentTree.nodes.singleWhere(
        (n) => n.type == ContentNodeType.chapter,
      );
      final harness = await ImportExportTestHarness.withNovel(
        snapshot,
        chapterTexts: {absoluteChapterPath(snapshot, chapter): '第1章\n'},
      );
      addTearDown(harness.dispose);
      final fake = FakeFilePickerPlatform()..saveFilePath = '/tmp/out.txt';
      installFakeFilePicker(fake);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExportPanel(
              controller: harness.controller,
              snapshot: snapshot,
              restrictVolumeId: null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 关掉「包含章节标题」选项，使空正文章节也跳过标题行。
      await tester.tap(find.text('包含章节标题'));
      await tester.pump();

      await tester.tap(find.text('导出'));
      // 同上：失败的 SnackBar 也会调度定时器，用 pump 推进即可。
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      // 空正文：组出来的文本为空 → saveFile 不应被调用。
      expect(fake.saveFileCalls, 0);
      expect(find.textContaining('所选章节均为空'), findsOneWidget);
    },
  );

  testWidgets(
    'export reports 无打开保存对话框 failure when saveFile throws PlatformException',
    (tester) async {
      final snapshot = buildSnapshot();
      final texts = await chapterTexts(snapshot);
      final harness = await ImportExportTestHarness.withNovel(
        snapshot,
        chapterTexts: texts,
      );
      addTearDown(harness.dispose);
      final fake = FakeFilePickerPlatform()..shouldThrowOnSaveFile = true;
      installFakeFilePicker(fake);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExportPanel(
              controller: harness.controller,
              snapshot: snapshot,
              restrictVolumeId: null,
              revealInFinder: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('导出'));
      // PlatformException 在内层 try 被专门捕获，弹失败提示后 return；与其它
      // 导出用例一致，用固定 pump 推进，避免长 SnackBar 定时器卡 pumpAndSettle。
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      expect(fake.saveFileCalls, 1);
      expect(find.textContaining('无法打开保存对话框'), findsOneWidget);
      expect(find.textContaining('已导出'), findsNothing);
    },
  );
}
