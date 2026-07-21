import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_app/features/import_export/import_flow.dart';
import 'package:lore_domain/lore_domain.dart';

import '_test_harness.dart';

void main() {
  testWidgets('import returns cleanly when picker is cancelled', (
    tester,
  ) async {
    final harness = await ImportExportTestHarness.empty();
    addTearDown(harness.dispose);
    final fake = FakeFilePickerPlatform(); // pickFilesResult stays null.
    installFakeFilePicker(fake);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: const SizedBox.shrink())),
    );
    await importTxtNovelFlow(
      tester.element(find.byType(Scaffold)),
      harness.controller,
    );
    await tester.pumpAndSettle();

    expect(fake.pickFilesCalls, 1);
    expect(harness.novelRepository.importedTitles, isEmpty);
    expect(harness.controller.novels, isEmpty);
    // 取消时不应弹出任何 SnackBar。
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('import parses and writes a TXT into the controller', (
    tester,
  ) async {
    final harness = await ImportExportTestHarness.empty();
    addTearDown(harness.dispose);
    final fake = FakeFilePickerPlatform()
      ..pickFilesResult = FilePickerResult([
        platformFileFromText('测试.txt', '第1章 测试\n正文内容\n\n第2章 二章\n内容二'),
      ]);
    installFakeFilePicker(fake);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: const SizedBox.shrink())),
    );
    await importTxtNovelFlow(
      tester.element(find.byType(Scaffold)),
      harness.controller,
    );
    await tester.pumpAndSettle();
    // controller.importNovel 触发了一次会话保存定时器（500ms），pump 过它
    // 以避免 _verifyInvariants 报告 pending timer。
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();

    expect(fake.pickFilesCalls, 1);
    expect(harness.novelRepository.importedTitles, ['测试']);
    expect(harness.controller.novels, hasLength(1));
    expect(harness.controller.novels.single.metadata.title, '测试');
    // 两个章节都已注册到 content tree。
    expect(
      harness.controller.novels.single.contentTree.nodes
          .where((n) => n.type == ContentNodeType.chapter)
          .length,
      2,
    );
    // 成功提示已展示。
    expect(find.textContaining('已导入'), findsOneWidget);
  });

  testWidgets(
    'import reports 无法打开文件选择器 when pickFiles throws PlatformException',
    (tester) async {
      final harness = await ImportExportTestHarness.empty();
      addTearDown(harness.dispose);
      final fake = FakeFilePickerPlatform()..shouldThrowOnPickFiles = true;
      installFakeFilePicker(fake);

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: const SizedBox.shrink())),
      );
      await importTxtNovelFlow(
        tester.element(find.byType(Scaffold)),
        harness.controller,
      );
      await tester.pumpAndSettle();

      // PlatformException 被专门捕获，转成"无法打开文件选择器"提示，且不写库。
      expect(fake.pickFilesCalls, 1);
      expect(find.textContaining('无法打开文件选择器'), findsOneWidget);
      expect(harness.novelRepository.importedTitles, isEmpty);
    },
  );
}
