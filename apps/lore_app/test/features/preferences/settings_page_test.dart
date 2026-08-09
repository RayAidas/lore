import 'dart:convert';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_app/features/preferences/settings_page.dart';
import 'package:lore_ui/lore_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'desktop settings use scroll-synced anchor navigation',
    (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: LoreTheme.light(),
            home: const Scaffold(body: SettingsContent()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('settings-navigation')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('settings-nav-appearance')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('settings-nav-layout')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('settings-nav-writing')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-nav-shortcuts')),
        findsOneWidget,
      );
      expect(find.text('主题'), findsOneWidget);
      expect(find.text('背景图片'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('add-background-images')),
        findsOneWidget,
      );
      expect(find.text('透明窗口'), findsNothing);
      // 默认章节格式已取消（固定 TXT），设置面板不再出现该行。
      expect(find.text('默认章节格式'), findsNothing);
      // 编辑器显示已并入排版；5 个大类之间各一条分隔线（5 段 → 4 条）。
      expect(find.text('字体'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget.runtimeType.toString() == '_SettingsSectionDivider',
        ),
        findsNWidgets(4),
      );
      // 组内不再有分割线：全面板 Divider 仅剩大类分隔线（VerticalDivider 是
      // 不同类型，不被 byType<Divider> 匹配）。
      expect(find.byType(Divider), findsNWidgets(4));
      expect(find.text('打字机模式'), findsOneWidget);
      expect(find.text('主题与编辑器显示'), findsNothing);
      expect(find.text('文档格式与段落样式'), findsNothing);
      expect(find.text('专注、目标与查找选项'), findsNothing);
      expect(find.text('新查找窗口的默认选项'), findsNothing);
      expect(find.byType(DropdownButton<dynamic>), findsNothing);
      // 主题已从下拉改为卡片选择器，6 个具名主题 + 「自动」齐全。
      expect(
        find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == '_ThemePicker',
        ),
        findsOneWidget,
      );
      expect(find.text('素白'), findsOneWidget);
      expect(find.text('纸张'), findsOneWidget);
      expect(find.text('夜间'), findsOneWidget);
      expect(find.text('霜华'), findsOneWidget);
      expect(find.text('翠微'), findsOneWidget);
      expect(find.text('墨渊'), findsOneWidget);
      expect(find.text('自动'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('settings-nav-selection-appearance')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('settings-nav-layout')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('settings-nav-selection-layout')),
        findsOneWidget,
      );
      final scrollTop = tester
          .getTopLeft(find.byKey(const ValueKey('settings-content-scroll')))
          .dy;
      final layoutTop = tester
          .getTopLeft(find.byKey(const ValueKey('settings-section-layout')))
          .dy;
      expect(layoutTop, closeTo(scrollTop, 2));

      await tester.tap(find.byKey(const ValueKey('settings-nav-writing')));
      await tester.pumpAndSettle();
      expect(find.text('打字机模式'), findsOneWidget);
      expect(find.text('每日字数目标'), findsOneWidget);
      expect(find.text('正则表达式'), findsOneWidget);
      expect(find.text('首行缩进两字'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('settings-nav-selection-writing')),
        findsOneWidget,
      );
      expect(find.byType(Switch), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == '_CompactSwitch',
        ),
        // 写作分组 5 个 + AI 分组「启用」开关 1 个。
        findsNWidgets(6),
      );

      await tester.drag(
        find.byKey(const ValueKey('settings-content-scroll')),
        const Offset(0, 1200),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('settings-nav-selection-appearance')),
        findsOneWidget,
      );
    },
    variant: const TargetPlatformVariant({TargetPlatform.macOS}),
  );

  testWidgets('settings dialog uses a restrained desktop size', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: LoreTheme.light(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSettingsPanel(context),
              child: const Text('打开设置'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开设置'));
    await tester.pumpAndSettle();

    final panelSize = tester.getSize(find.byKey(const ValueKey('lore-panel')));
    expect(panelSize.width, closeTo(760, 1));
    expect(panelSize.height, lessThanOrEqualTo(648));
    expect(find.text('外观、编辑器与写作偏好'), findsNothing);
  });

  testWidgets('background gallery shows saved images and changes selection', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'lore.app.preferences': jsonEncode({
        'schemaVersion': 7,
        'themeMode': 'light',
        'defaultChapterFormat': 'text',
        'editorLineHeight': 1.45,
        'editorFontSize': 18,
        'editorContentWidth': 900,
        'dailyWordGoal': 2000,
        'findMatchCase': false,
        'findUseRegex': false,
        'backgroundMode': 'image',
        'backgroundImagePaths': [
          '/managed/background-1.jpg',
          '/managed/background-2.jpg',
        ],
        'backgroundImagePath': '/managed/background-1.jpg',
        'backgroundOpacity': 0.84,
        'backgroundImageDimness': 0.2,
      }),
    });
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: LoreTheme.light(),
          home: const Scaffold(body: SettingsContent()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('删除背景图片'), findsNWidgets(2));
    final first = find.byKey(
      const ValueKey('background-thumbnail-/managed/background-1.jpg'),
    );
    final second = find.byKey(
      const ValueKey('background-thumbnail-/managed/background-2.jpg'),
    );
    expect(
      tester.getSemantics(first).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(
      tester.getSemantics(second).flagsCollection.isSelected,
      isNot(Tristate.isTrue),
    );

    await tester.tap(second);
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(first).flagsCollection.isSelected,
      isNot(Tristate.isTrue),
    );
    expect(
      tester.getSemantics(second).flagsCollection.isSelected,
      Tristate.isTrue,
    );
  });

  testWidgets(
    'tapping the selected background thumbnail clears the selection',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'lore.app.preferences': jsonEncode({
          'schemaVersion': 10,
          'themeMode': 'light',
          'defaultChapterFormat': 'text',
          'editorLineHeight': 1.45,
          'editorFontSize': 18,
          'editorContentWidth': 900,
          'dailyWordGoal': 2000,
          'findMatchCase': false,
          'findUseRegex': false,
          'backgroundImagePaths': ['/managed/background-1.jpg'],
          'backgroundImagePath': '/managed/background-1.jpg',
          'backgroundOpacity': 0.84,
          'backgroundImageDimness': 0.2,
        }),
      });
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: LoreTheme.light(),
            home: const Scaffold(body: SettingsContent()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 启用图片背景时，两个调节滑块应可见。
      expect(find.text('界面不透明度'), findsOneWidget);
      expect(find.text('图片遮罩'), findsOneWidget);

      final selected = find.byKey(
        const ValueKey('background-thumbnail-/managed/background-1.jpg'),
      );
      expect(
        tester.getSemantics(selected).flagsCollection.isSelected,
        Tristate.isTrue,
      );

      // 再次点击当前选中的缩略图 → 取消选中，回到纯主题色底。
      await tester.tap(selected);
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(selected).flagsCollection.isSelected,
        isNot(Tristate.isTrue),
      );
      // 取消后图片背景关闭，两个滑块随之消失。
      expect(find.text('界面不透明度'), findsNothing);
      expect(find.text('图片遮罩'), findsNothing);
    },
  );

  testWidgets('interface dropdown switches provider, model dropdown lists its models', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: LoreTheme.light(),
          home: const Scaffold(body: SettingsContent()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 默认配置命中 OpenAI 提供商，模型下拉展示其默认模型。
    await tester.tap(find.byKey(const ValueKey('settings-nav-ai')));
    await tester.pumpAndSettle();
    final providerDropdown = find.byKey(
      const ValueKey('ai-provider-dropdown'),
    );
    final modelDropdown = find.byKey(const ValueKey('ai-model-dropdown'));
    expect(providerDropdown, findsOneWidget);
    expect(modelDropdown, findsOneWidget);
    expect(find.byTooltip('当前：OpenAI'), findsOneWidget);
    expect(find.byTooltip('当前：gpt-4o-mini'), findsOneWidget);

    // 接口地址选 DeepSeek → 写入其地址与默认模型，模型下拉切到 DeepSeek 列表。
    await tester.tap(providerDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('DeepSeek'));
    await tester.pumpAndSettle();

    Future<Map<String, Object?>> stored() async => jsonDecode(
      (await SharedPreferences.getInstance()).getString('lore.agent.config')!,
    ) as Map<String, Object?>;
    expect((await stored())['baseUrl'], 'https://api.deepseek.com');
    expect((await stored())['model'], 'deepseek-chat');
    expect(find.byTooltip('当前：DeepSeek'), findsOneWidget);
    expect(find.byTooltip('当前：deepseek-chat'), findsOneWidget);

    // 模型下拉选同提供商的另一模型 → 只改模型名、保留当前接口地址。
    await tester.tap(modelDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('deepseek-reasoner'));
    await tester.pumpAndSettle();
    expect((await stored())['model'], 'deepseek-reasoner');
    expect((await stored())['baseUrl'], 'https://api.deepseek.com');
    expect(find.byTooltip('当前：deepseek-reasoner'), findsOneWidget);

    // 「自定义模型…」→ 手动输入，只改模型名、保留当前接口地址。
    await tester.tap(modelDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义模型…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'my-custom-model');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect((await stored())['model'], 'my-custom-model');
    expect((await stored())['baseUrl'], 'https://api.deepseek.com');
  });

  testWidgets('custom interface falls back model dropdown to custom input', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: LoreTheme.light(),
          home: const Scaffold(body: SettingsContent()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('settings-nav-ai')));
    await tester.pumpAndSettle();

    // 接口地址选「自定义接口…」→ 手动输入地址，模型下拉随之退化为自定义项。
    await tester.tap(find.byKey(const ValueKey('ai-provider-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义接口…'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'https://my-proxy.example.com/v1',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final stored = jsonDecode(
      (await SharedPreferences.getInstance()).getString('lore.agent.config')!,
    ) as Map<String, Object?>;
    expect(stored['baseUrl'], 'https://my-proxy.example.com/v1');
    // 地址不再命中任何提供商 → 接口下拉显示自定义，模型下拉只能自定义填写。
    expect(find.byTooltip('当前：自定义接口…'), findsOneWidget);
    expect(find.byTooltip('当前：自定义模型…'), findsOneWidget);
  });

  testWidgets('tapping a theme card persists the selection', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: LoreTheme.light(),
          home: const Scaffold(body: SettingsContent()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 默认跟随系统；点「墨渊」卡片应切换并落盘。
    expect(find.text('墨渊'), findsOneWidget);
    await tester.tap(find.text('墨渊'));
    await tester.pumpAndSettle();

    final stored = await SharedPreferences.getInstance();
    final blob = jsonDecode(stored.getString('lore.app.preferences')!);
    expect(blob['themeMode'], 'ink');
  });

  testWidgets(
    'scrolling to bottom selects the last section',
    (tester) async {
      // 短视口让内容可滚动；锁定"手动滚到底 → 末项 writing 被选中"路径
      // （extentAfter≈0 兜底 + 手动滚动同步导航两条此前未覆盖的逻辑）。
      tester.view.physicalSize = const Size(900, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: LoreTheme.light(),
            home: const Scaffold(body: SettingsContent()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('settings-nav-selection-appearance')),
        findsOneWidget,
      );

      // 向上拖（指针 dy 负 → 内容下滚）到底。
      await tester.drag(
        find.byKey(const ValueKey('settings-content-scroll')),
        const Offset(0, -5000),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('settings-nav-selection-shortcuts')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-nav-selection-appearance')),
        findsNothing,
      );
    },
    variant: const TargetPlatformVariant({TargetPlatform.macOS}),
  );
}
