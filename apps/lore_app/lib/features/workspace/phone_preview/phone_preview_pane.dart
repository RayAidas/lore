import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_editor/lore_editor.dart';

import '../../preferences/font_options.dart';
import '../../preferences/preferences_providers.dart';
import '../workspace_controller.dart';
import 'phone_device.dart';
import 'phone_device_frame.dart';

/// 手机预览面板：把当前 tab 的 `.txt` 小说章节以手机阅读器样式呈现。
///
/// 仅在桌面端右侧检查器工具栏出现（随 `WorkspaceInspectorRail` 桌面限定）。
/// 内容来源是当前活动文档（[WorkspaceController.activeDocument]）：当它是
/// `.txt` 章节（chapterNumber 非空且非 markdown）时，在手机外框内渲染
/// 「第N章 副标题」+ 正文阅读流；否则提示空态。编辑器正文变化时实时刷新。
final class PhonePreviewPane extends ConsumerStatefulWidget {
  const PhonePreviewPane({required this.controller, super.key});

  final WorkspaceController controller;

  @override
  ConsumerState<PhonePreviewPane> createState() => _PhonePreviewPaneState();
}

final class _PhonePreviewPaneState extends ConsumerState<PhonePreviewPane> {
  /// 当前选中的机型（默认 iPhone 15）。
  PhoneDevice _device = PhoneDevice.presets[1];

  /// 当前选中的屏幕外形（默认灵动岛）。
  PhoneFrameStyle _frameStyle = PhoneFrameStyle.dynamicIsland;

  WorkspaceController get controller => widget.controller;

  /// 从应用偏好派生编辑器排版，与 `DocumentPane._resolveEditorStyle` 同口径，
  /// 保证手机预览的字号 / 行高 / 字体 / 段距与编辑态一致。
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
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: cs.surface,
      child: Row(
        children: [
          Icon(Icons.smartphone_outlined, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            '手机预览',
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
    // 手机与面板边界 / 分隔线之间留出呼吸空间，外层投影也有处可落。
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: FittedBox(
          fit: BoxFit.contain,
          child: PhoneDeviceFrame(
            device: _device,
            frameStyle: _frameStyle,
            child: _PhoneChapterContent(document: document, style: style),
          ),
        ),
      ),
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

  /// 标签 + 选择器一行：左侧窄标签，右侧选择器（按内容自适应宽，溢出省略）。
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
    // value 一般都在 items 中；若未同步则回退首项，避免构造期崩溃。
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

/// 手机屏幕内的章节内容：标题（第N章 副标题）+ 正文阅读流。
final class _PhoneChapterContent extends StatelessWidget {
  const _PhoneChapterContent({required this.document, required this.style});

  final OpenDocument document;
  final EditorStyle style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = EditorTypography.titleText(style, theme);
    final title = ChapterTitleText.titleLine(
      document.chapterNumber!,
      document.chapterTitleSubtitle,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, 14, 20, style.titleBottomSpacing),
          child: Text(title, style: titleStyle),
        ),
        Expanded(
          child: LoreReadingFlowPreview(
            data: document.editorController.text,
            style: style,
          ),
        ),
      ],
    );
  }
}
