import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_editor/lore_editor.dart';

import '../../preferences/font_options.dart';
import '../../preferences/preferences_providers.dart';
import '../workspace_controller.dart';
import 'phone_device.dart';
import 'phone_device_frame.dart';
import 'phone_preview_page_sync.dart';
import 'phone_preview_paginator.dart';
import 'phone_preview_scroll_sync.dart';

/// 预览阅读方式：连续上下滚动，或左右翻页（电子书分页）。
enum PhonePreviewMode {
  scroll('滚动'),
  page('翻页');

  const PhonePreviewMode(this.label);
  final String label;
}

/// 手机预览面板：把当前 tab 的 `.txt` 小说章节以手机阅读器样式呈现。
///
/// 仅在桌面端右侧检查器工具栏出现（随 `WorkspaceInspectorRail` 桌面限定）。
/// 内容来源是当前活动文档（[WorkspaceController.activeDocument]）：当它是
/// `.txt` 章节（chapterNumber 非空且非 markdown）时，在手机外框内渲染
/// 「第N章 副标题」+ 正文；否则提示空态。编辑器正文变化时实时刷新。
///
/// 两种阅读方式：
/// - **滚动**（默认）：`LoreReadingFlowPreview` 连续滚动，与编辑器**双向百分比**
///   滚动同步（`PhonePreviewScrollSync`）。
/// - **翻页**：`TextPainter` 行级分页 + `PageView` 左右翻页，与编辑器**单向**
///   页号同步（`PhonePreviewPageSync`，编辑器滚动 → 翻到对应页）。
final class PhonePreviewPane extends ConsumerStatefulWidget {
  const PhonePreviewPane({required this.controller, super.key});

  final WorkspaceController controller;

  @override
  ConsumerState<PhonePreviewPane> createState() => _PhonePreviewPaneState();
}

final class _PhonePreviewPaneState extends ConsumerState<PhonePreviewPane> {
  PhoneDevice _device = PhoneDevice.presets[1];
  PhoneFrameStyle _frameStyle = PhoneFrameStyle.dynamicIsland;
  PhonePreviewMode _mode = PhonePreviewMode.scroll;

  /// 滚动模式的预览控制器与同步。
  final ScrollController _previewScrollController = ScrollController();
  late final PhonePreviewScrollSync _scrollSync;

  /// 翻页模式的页面控制器与同步。
  final PageController _pageController = PageController();
  late final PhonePreviewPageSync _pageSync;

  /// 当前页号（翻页模式，用于页码指示）。
  int _currentPage = 0;

  /// 分页缓存：正文 / 机型 / 排版变化时重算（record 结构相等作 key）。
  _PageKey? _pageKey;
  List<PhonePreviewPage> _cachedPages = const [];

  WorkspaceController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _scrollSync = PhonePreviewScrollSync(target: _previewScrollController);
    _pageSync = PhonePreviewPageSync(
      target: _pageController,
      pageCount: () => _cachedPages.isEmpty ? 1 : _cachedPages.length,
    );
    controller.addListener(_onWorkspaceChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureBound();
    });
  }

  @override
  void dispose() {
    controller.removeListener(_onWorkspaceChanged);
    _scrollSync.dispose();
    _pageSync.dispose();
    _previewScrollController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onWorkspaceChanged() {
    if (!mounted) return;
    _ensureBound();
  }

  /// 按当前模式把活动文档的编辑器滚动控制器绑到对应的同步；另一模式解绑。
  void _ensureBound() {
    final doc = controller.activeDocument;
    final editor = (doc != null && doc.chapterNumber != null && !doc.isMarkdown)
        ? doc.scrollController
        : null;
    if (_mode == PhonePreviewMode.page) {
      _scrollSync.bind(null);
      _pageSync.bind(editor);
    } else {
      _pageSync.bind(null);
      _scrollSync.bind(editor);
    }
  }

  EditorStyle _resolveEditorStyle(AppPreferences prefs) {
    final fontOption = AppFontOptions.resolve(prefs.editorFontFamily);
    return const EditorStyle.defaults().copyWith(
      lineHeight: prefs.editorLineHeight,
      fontSize: prefs.editorFontSize,
      contentWidth: prefs.editorContentWidth,
      fontFamily: fontOption.fontFamily,
      fontFamilyFallback: fontOption.fontFamilyFallback,
      firstLineIndent: prefs.firstLineIndent,
      paragraphSpacing: prefs.paragraphSpacing,
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefs =
        ref.watch(appPreferencesProvider).value ?? AppPreferences.defaults();
    final editorStyle = _resolveEditorStyle(prefs);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final document = controller.activeDocument;
        final content = document == null
            ? _buildEmpty(context)
            : ListenableBuilder(
                listenable: document.editorController,
                builder: (context, _) {
                  final previewable =
                      document.chapterNumber != null && !document.isMarkdown;
                  return previewable
                      ? _buildPhone(context, document, editorStyle)
                      : _buildEmpty(context);
                },
              );
        return Column(
          children: [
            _buildHeader(context),
            const Divider(height: 1),
            Expanded(child: content),
            const Divider(height: 1),
            _buildControls(context),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // 翻页模式在标题后挂页码指示。页数可能刚缩减，钳到有效范围避免显示「6/3」。
    final clampedPage = _cachedPages.isEmpty
        ? 0
        : (_currentPage < _cachedPages.length
              ? _currentPage
              : _cachedPages.length - 1);
    final pageHint = _mode == PhonePreviewMode.page && _cachedPages.isNotEmpty
        ? '  ·  ${clampedPage + 1}/${_cachedPages.length}'
        : '';
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: cs.surface,
      child: Row(
        children: [
          Icon(Icons.smartphone_outlined, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            '手机预览$pageHint',
            style: theme.textTheme.titleSmall?.copyWith(fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildPhone(
    BuildContext context,
    OpenDocument document,
    EditorStyle style,
  ) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: FittedBox(
          fit: BoxFit.contain,
          child: PhoneDeviceFrame(
            device: _device,
            frameStyle: _frameStyle,
            child: _mode == PhonePreviewMode.page
                ? MediaQuery(
                    // 翻页内容按固定盒子分页（测量为 textScaler=1）；禁用环境字号
                    // 缩放，避免渲染缩放后溢出页面盒、与测量不一致。
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(1)),
                    child: _PhoneChapterPages(
                      pageController: _pageController,
                      pages: _resolvePages(context, document, style),
                      style: style,
                      document: document,
                      onPageChanged: (i) => setState(() => _currentPage = i),
                    ),
                  )
                : _PhoneChapterContent(
                    document: document,
                    style: style,
                    scrollController: _previewScrollController,
                  ),
          ),
        ),
      ),
    );
  }

  /// 翻页模式的分页结果（按正文 / 机型 / 排版缓存，key 命中则复用）。
  List<PhonePreviewPage> _resolvePages(
    BuildContext context,
    OpenDocument document,
    EditorStyle style,
  ) {
    // key 不含 document 身份（chapterNumber + text 已足够），避免文档重新实例化
    // 时无谓重算；含 brightness，切深浅主题时重排。
    final key = (
      text: document.editorController.text,
      deviceW: _device.width,
      deviceH: _device.height,
      fontSize: style.fontSize,
      lineHeight: style.lineHeight,
      fontFamily: style.fontFamily ?? '',
      paragraphSpacing: style.paragraphSpacing,
      indent: style.firstLineIndent,
      chapterNumber: document.chapterNumber!,
      subtitle: document.chapterTitleSubtitle,
      brightness: Theme.of(context).brightness,
    );
    if (_pageKey == key) return _cachedPages;
    _pageKey = key;
    _cachedPages = _paginate(context, document, style);
    // 页数缩减后（删字）当前页可能越界：钳到有效范围并延一帧跳过去，避免「6/3」。
    if (_cachedPages.isNotEmpty && _currentPage >= _cachedPages.length) {
      _currentPage = _cachedPages.length - 1;
      final target = _currentPage;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(target);
        }
      });
    }
    return _cachedPages;
  }

  /// 计算分页：页面内容盒 = 机型屏幕扣除状态栏与内边距；第 1 页再扣标题区。
  List<PhonePreviewPage> _paginate(
    BuildContext context,
    OpenDocument document,
    EditorStyle style,
  ) {
    const hPad = 20.0, topPad = 16.0, bottomPad = 24.0;
    final theme = Theme.of(context);
    final contentWidth = _device.width - hPad * 2;
    final contentHeight =
        _device.height - PhoneDeviceFrame.statusBarHeight - topPad - bottomPad;

    final titleStyle = EditorTypography.titleText(style, theme);
    final title = ChapterTitleText.titleLine(
      document.chapterNumber!,
      document.chapterTitleSubtitle,
    );
    final tp = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(text: title, style: titleStyle)
      ..layout(maxWidth: contentWidth);
    final titleHeight = tp.height;
    tp.dispose();

    // 预留安全余量：分页器测量（TextPainter）与实际渲染（Column 内多个 Text）
    // 间有亚像素差，分页器还允许 +0.5px 容差。按满高填会让渲染溢出底部 0.x px
    // 报错。每页少填 2px 吸收，视觉上无感。
    const pageSafetyMargin = 2.0;
    final paginator = PhonePreviewPaginator(
      boxWidth: contentWidth,
      pageHeight: contentHeight - pageSafetyMargin,
      firstPageHeight:
          (contentHeight -
                  titleHeight -
                  style.titleBottomSpacing -
                  pageSafetyMargin)
              .clamp(0.0, contentHeight),
      style: EditorTypography.bodyText(style, theme) ?? const TextStyle(),
      paragraphGap: style.paragraphSpacing * style.fontSize,
      paragraphIndent: style.firstLineIndent ? '　　' : '',
    );
    return paginator.paginate(
      LoreReadingFlowPreview.splitParagraphs(document.editorController.text),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.smartphone_outlined, size: 40, color: cs.outline),
            const SizedBox(height: 12),
            Text(
              '请打开一个小说章节',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '仅支持 .txt 章节的手机预览。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      color: cs.surfaceContainerLowest,
      child: Column(
        children: [
          _selectorRow(
            context,
            label: '模式',
            value: _mode,
            items: [
              for (final m in PhonePreviewMode.values)
                _PhonePreviewOption(m, m.label),
            ],
            onChanged: (m) => setState(() {
              _mode = m;
              // 切到翻页模式时重置页号；页号同步会随即按编辑器位置跳到对应页。
              if (m == PhonePreviewMode.page) _currentPage = 0;
              _ensureBound();
            }),
          ),
          const SizedBox(height: 8),
          _selectorRow(
            context,
            label: '机型',
            value: _device,
            items: [
              for (final d in PhoneDevice.presets)
                _PhonePreviewOption(d, d.name),
            ],
            onChanged: (device) => setState(() => _device = device),
          ),
          const SizedBox(height: 8),
          _selectorRow(
            context,
            label: '外形',
            value: _frameStyle,
            items: [
              for (final f in PhoneFrameStyle.values)
                _PhonePreviewOption(f, f.label),
            ],
            onChanged: (style) => setState(() => _frameStyle = style),
          ),
        ],
      ),
    );
  }

  Widget _selectorRow<T>(
    BuildContext context, {
    required String label,
    required T value,
    required List<_PhonePreviewOption<T>> items,
    required ValueChanged<T> onChanged,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 36,
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: _PhonePreviewDropdown<T>(
            value: value,
            items: items,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// 分页缓存 key（record 结构相等）。chapterNumber + text 已标识内容，故不含
/// document 身份（避免文档重新实例化时无谓重算）；含 brightness 以便切主题重排。
typedef _PageKey = ({
  String text,
  double deviceW,
  double deviceH,
  double fontSize,
  double lineHeight,
  String fontFamily,
  double paragraphSpacing,
  bool indent,
  int chapterNumber,
  String subtitle,
  Brightness brightness,
});

/// 选项：值 + 展示标签。
final class _PhonePreviewOption<T> {
  const _PhonePreviewOption(this.value, this.label);

  final T value;
  final String label;
}

/// 紧凑选择器：与设置页 `_Dropdown` 同款视觉——圆角芯片触发器 + 下方弹出菜单，
/// 当前项带勾。按内容自适应宽度（放在 [Flexible] 中可在窄面板内省略溢出）。
final class _PhonePreviewDropdown<T> extends StatelessWidget {
  const _PhonePreviewDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    super.key,
  });

  final T value;
  final List<_PhonePreviewOption<T>> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    var selected = items.first;
    for (final item in items) {
      if (item.value == value) {
        selected = item;
        break;
      }
    }
    return PopupMenuButton<T>(
      tooltip: '当前：${selected.label}',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 4),
      constraints: const BoxConstraints(minWidth: 132, maxWidth: 240),
      color: cs.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: cs.outlineVariant),
      ),
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final item in items)
          PopupMenuItem<T>(
            value: item.value,
            height: 38,
            child: Row(
              children: [
                Expanded(
                  child: Text(item.label, overflow: TextOverflow.ellipsis),
                ),
                if (item.value == value)
                  Icon(Icons.check_rounded, size: 16, color: cs.primary),
              ],
            ),
          ),
      ],
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: DefaultTextStyle.merge(
                style: theme.textTheme.bodySmall ?? const TextStyle(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                child: Text(selected.label),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 17,
              color: cs.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// 滚动模式：标题（经 header）+ 正文阅读流，共享一个滚动视图，标题随正文滚动。
final class _PhoneChapterContent extends StatelessWidget {
  const _PhoneChapterContent({
    required this.document,
    required this.style,
    required this.scrollController,
  });

  final OpenDocument document;
  final EditorStyle style;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = EditorTypography.titleText(style, theme);
    final title = ChapterTitleText.titleLine(
      document.chapterNumber!,
      document.chapterTitleSubtitle,
    );
    return LoreReadingFlowPreview(
      scrollController: scrollController,
      data: document.editorController.text,
      style: style,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      header: Padding(
        padding: EdgeInsets.only(bottom: style.titleBottomSpacing),
        child: Text(title, style: titleStyle),
      ),
    );
  }
}

/// 翻页模式：[PageView] 横向翻页，每页渲染分页段；第 1 页顶部带章节标题。
final class _PhoneChapterPages extends StatelessWidget {
  const _PhoneChapterPages({
    required this.pageController,
    required this.pages,
    required this.style,
    required this.document,
    required this.onPageChanged,
  });

  final PageController pageController;
  final List<PhonePreviewPage> pages;
  final EditorStyle style;
  final OpenDocument document;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    // 正文为空时仍渲染一页（仅标题），避免空白。
    final renderPages = pages.isEmpty
        ? const [PhonePreviewPage(segments: [])]
        : pages;
    return PageView.builder(
      controller: pageController,
      itemCount: renderPages.length,
      onPageChanged: onPageChanged,
      itemBuilder: (context, index) => _PageBody(
        page: renderPages[index],
        showTitle: index == 0,
        style: style,
        document: document,
      ),
    );
  }
}

/// 单页内容：可选标题（首页）+ 分页段列表（段间间距）。
final class _PageBody extends StatelessWidget {
  const _PageBody({
    required this.page,
    required this.showTitle,
    required this.style,
    required this.document,
  });

  final PhonePreviewPage page;
  final bool showTitle;
  final EditorStyle style;
  final OpenDocument document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paragraphStyle =
        EditorTypography.bodyText(style, theme) ?? const TextStyle();
    final gap = style.paragraphSpacing * style.fontSize;
    final title = ChapterTitleText.titleLine(
      document.chapterNumber!,
      document.chapterTitleSubtitle,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTitle)
            Padding(
              padding: EdgeInsets.only(bottom: style.titleBottomSpacing),
              child: Text(
                title,
                style: EditorTypography.titleText(style, theme),
              ),
            ),
          for (var j = 0; j < page.segments.length; j++) ...[
            if (j > 0 && page.segments[j].newParagraph) SizedBox(height: gap),
            Text(page.segments[j].text, style: paragraphStyle),
          ],
        ],
      ),
    );
  }
}
