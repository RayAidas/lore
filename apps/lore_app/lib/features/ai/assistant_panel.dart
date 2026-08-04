import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_editor/lore_editor.dart';
import 'package:lore_ui/lore_ui.dart';

import '../preferences/settings_page.dart';
import '../workspace/workspace_controller.dart';
import 'ai_providers.dart';

/// 发送给模型的上下文范围。
enum AgentContextMode { selection, document }

/// 生成结果应用回文档的目标位置。
enum AgentApplyTarget {
  /// 替换当前选区（选区折叠时退化为在光标处插入）。
  replaceSelection,

  /// 插入到光标处。
  insertAtCursor,

  /// 追加到文档末尾。
  append,
}

/// 以辅助面板弹层打开写作助手（窄屏自动降级为 bottom sheet），移动端入口。
Future<void> showAiAssistantSheet(
  BuildContext context,
  WorkspaceController controller,
) {
  return showLorePanelSheet<void>(
    context: context,
    title: 'AI 写作助手',
    icon: Icons.auto_awesome_outlined,
    maxWidth: 560,
    child: AiAssistantPanel(controller: controller),
  );
}

/// 工作区「助手」面板：预置写作指令 + 自定义指令 + 结果应用回文档。
///
/// 桌面端嵌入右侧 inspector；移动端经 [showAiAssistantSheet] 以面板弹层展示。
/// 第一版不做流式输出与多轮对话历史：每次请求是「指令 + 当前上下文」的单轮，
/// 结果可一键替换选区 / 插入 / 追加（自动保存兜底）。
final class AiAssistantPanel extends ConsumerStatefulWidget {
  const AiAssistantPanel({required this.controller, super.key});

  final WorkspaceController controller;

  @override
  ConsumerState<AiAssistantPanel> createState() => _AiAssistantPanelState();
}

final class _AiAssistantPanelState extends ConsumerState<AiAssistantPanel> {
  final TextEditingController _promptController = TextEditingController();
  AgentContextMode _contextMode = AgentContextMode.selection;
  bool _busy = false;
  String? _result;
  String? _error;

  WritingAgentAction? _lastAction;
  String? _lastCustom;

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  WorkspaceController get controller => widget.controller;

  OpenDocument? get _activeDocument => controller.activeDocument;

  @override
  Widget build(BuildContext context) {
    final agentAsync = ref.watch(agentConfigProvider);
    final configState = agentAsync.value;
    if (agentAsync.hasError) {
      return _ConfigLoadErrorView(
        onRetry: () => ref.invalidate(agentConfigProvider),
      );
    }
    if (configState == null) {
      // 静态占位而非无限转圈：配置为本地快速读取，避免动画阻塞测试 settle。
      return const Center(child: Text('正在加载 AI 配置…'));
    }
    if (!configState.config.enabled || !configState.hasApiKey) {
      return _NotConfiguredView(onOpenSettings: _openSettings);
    }
    final doc = _activeDocument;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ContextSection(
          mode: _contextMode,
          document: doc,
          controllerListenable: Listenable.merge([
            controller,
            if (doc != null) doc.editorController,
          ]),
          onModeChanged: (mode) => setState(() => _contextMode = mode),
        ),
        const SizedBox(height: 14),
        _ActionSection(
          enabled: doc != null && !_busy,
          onAction: _runAction,
        ),
        const SizedBox(height: 14),
        _CustomPromptSection(
          controller: _promptController,
          busy: _busy,
          onSend: _runCustom,
        ),
        const SizedBox(height: 14),
        if (_busy) const _BusyIndicator(),
        if (_error != null) _ErrorSection(message: _error!, onRetry: _retry),
        if (_result != null) ...[
          const SizedBox(height: 4),
          _ResultSection(
            text: _result!,
            hasSelection: _hasNonCollapsedSelection(doc),
            documentOpen: doc != null,
            busy: _busy,
            onApply: (target) => _apply(doc!, target),
            onCopy: _copyResult,
            onClear: () => setState(() {
              _result = null;
              _error = null;
              // 一并清空自定义指令输入框，避免残留指令影响下一次请求。
              _promptController.clear();
            }),
          ),
        ],
      ],
    );
  }

  bool _hasNonCollapsedSelection(OpenDocument? doc) {
    if (doc == null) {
      return false;
    }
    final selection = doc.editorController.selection;
    return selection.isValid && !selection.isCollapsed;
  }

  void _openSettings() {
    showSettingsPanel(context, initialSection: 'ai');
  }

  /// 读取当前上下文文本（按 [_contextMode]，选区不可用时回落到当前文档）。
  ({String text, int count, bool fromSelection}) _currentContext() {
    final doc = _activeDocument;
    if (doc == null) {
      return (text: '', count: 0, fromSelection: false);
    }
    if (_contextMode == AgentContextMode.selection) {
      final selection = doc.editorController.selection;
      if (selection.isValid && !selection.isCollapsed) {
        final text = doc.editorController.text.substring(
          selection.start,
          selection.end,
        );
        return (text: text, count: text.length, fromSelection: true);
      }
    }
    final text = _documentContextText(doc);
    return (text: text, count: text.length, fromSelection: false);
  }

  /// 章节文档把标题行（编辑器只持正文）拼回去，给模型完整语境。
  String _documentContextText(OpenDocument doc) {
    final number = doc.chapterNumber;
    if (number == null) {
      return doc.editorController.text;
    }
    return ChapterTitleText.compose(
      number,
      doc.chapterTitleSubtitle,
      doc.editorController.text,
      markdown: doc.isMarkdown,
    );
  }

  Future<void> _runAction(WritingAgentAction action) {
    return _execute(action: action);
  }

  Future<void> _runCustom() {
    final instruction = _promptController.text.trim();
    if (instruction.isEmpty) {
      return Future.value();
    }
    return _execute(custom: instruction);
  }

  void _retry() {
    _execute(action: _lastAction, custom: _lastCustom);
  }

  Future<void> _execute({WritingAgentAction? action, String? custom}) async {
    if (action == null && custom == null) {
      return;
    }
    final configState = ref.read(agentConfigProvider).value;
    if (configState == null || !configState.config.enabled || !configState.hasApiKey) {
      setState(() {
        _error = 'AI 未启用或未设置 API Key，请先到设置中配置';
        _result = null;
      });
      return;
    }
    final contextInfo = _currentContext();
    if (contextInfo.text.trim().isEmpty) {
      setState(() {
        _error = '没有可用的上下文：请先选中文字或打开一个文档';
        _result = null;
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _result = null;
      _lastAction = action;
      _lastCustom = custom;
    });

    final service = ref.read(writingAgentServiceProvider);
    try {
      final String text;
      if (action != null) {
        text = await service.runAction(
          action: action,
          contextText: contextInfo.text,
          config: configState.config,
          apiKey: configState.config.apiKey,
        );
      } else if (custom != null) {
        text = await service.runCustom(
          instruction: custom,
          contextText: contextInfo.text,
          config: configState.config,
          apiKey: configState.config.apiKey,
        );
      } else {
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _result = text;
        _busy = false;
      });
    } on AiRequestException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.message;
        _busy = false;
      });
    }
  }

  Future<void> _copyResult() async {
    final text = _result;
    if (text == null) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      LoreToast.success(context, '已复制到剪贴板');
    }
  }

  void _apply(OpenDocument doc, AgentApplyTarget target) {
    final text = _result;
    if (text == null || text.isEmpty) {
      return;
    }
    final editor = doc.editorController;
    final selection = editor.selection;
    if (editor is LoreLargeTextController) {
      switch (target) {
        case AgentApplyTarget.replaceSelection:
          if (selection.isValid && !selection.isCollapsed) {
            editor.replaceRange(selection.start, selection.end, text);
          } else {
            editor.replaceSelection(text);
          }
        case AgentApplyTarget.insertAtCursor:
          editor.replaceSelection(text);
        case AgentApplyTarget.append:
          editor.replaceRange(editor.length, editor.length, '\n$text');
      }
    } else if (editor is LoreTextController) {
      editor.value = switch (target) {
        AgentApplyTarget.replaceSelection ||
        AgentApplyTarget.insertAtCursor => TextEditingValue(
          text: selection.isValid
              ? editor.text
                    .replaceRange(selection.start, selection.end, text)
              : editor.text + text,
          selection: TextSelection.collapsed(
            offset: (selection.isValid ? selection.start : editor.text.length) +
                text.length,
          ),
        ),
        AgentApplyTarget.append => TextEditingValue(
          text: '${editor.text}\n$text',
          selection: TextSelection.collapsed(offset: editor.text.length + 1 + text.length),
        ),
      };
    } else {
      if (context.mounted) {
        LoreToast.error(context, '暂不支持应用到此类型的文档');
      }
      return;
    }
    if (context.mounted) {
      LoreToast.success(context, '已应用到文档');
    }
  }
}

/// 上下文范围行：显示将发送的内容概要，可切换「选中文字 / 当前章节」。
final class _ContextSection extends StatelessWidget {
  const _ContextSection({
    required this.mode,
    required this.document,
    required this.controllerListenable,
    required this.onModeChanged,
  });

  final AgentContextMode mode;
  final OpenDocument? document;
  final Listenable controllerListenable;
  final ValueChanged<AgentContextMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('上下文', style: theme.textTheme.labelMedium),
        const SizedBox(height: 8),
        ListenableBuilder(
          listenable: controllerListenable,
          builder: (context, _) {
            final doc = document;
            if (doc == null) {
              return Text(
                '未打开文档',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              );
            }
            final selection = doc.editorController.selection;
            final hasSelection = selection.isValid && !selection.isCollapsed;
            final selected = hasSelection
                ? selection.end - selection.start
                : 0;
            final bodyLength = doc.editorController.length;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _ContextChip(
                  label: '选中文字',
                  count: selected,
                  available: hasSelection,
                  selected: mode == AgentContextMode.selection && hasSelection,
                  onTap: hasSelection
                      ? () => onModeChanged(AgentContextMode.selection)
                      : null,
                ),
                _ContextChip(
                  label: '当前章节',
                  count: bodyLength,
                  available: true,
                  selected: mode == AgentContextMode.document,
                  onTap: () => onModeChanged(AgentContextMode.document),
                ),
                const SizedBox(width: 4),
                Text(
                  '将发送：${mode == AgentContextMode.selection && hasSelection ? '选中文字' : '整篇正文'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

final class _ContextChip extends StatelessWidget {
  const _ContextChip({
    required this.label,
    required this.count,
    required this.available,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool available;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveSelected = selected && available;
    return Material(
      color: effectiveSelected
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            '$label${count > 0 ? ' · $count 字' : ''}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: effectiveSelected
                  ? colorScheme.onPrimaryContainer
                  : available
                  ? colorScheme.onSurface
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
              fontWeight: effectiveSelected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// 预置快捷写作指令。
final class _ActionSection extends StatelessWidget {
  const _ActionSection({
    required this.enabled,
    required this.onAction,
  });

  final bool enabled;
  final ValueChanged<WritingAgentAction> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actions = const [
      (WritingAgentAction.proofread, '校对', Icons.spellcheck_outlined),
      (WritingAgentAction.polish, '润色', Icons.auto_awesome_outlined),
      (WritingAgentAction.summarize, '总结', Icons.compress_outlined),
      (WritingAgentAction.continueWriting, '续写', Icons.edit_note_outlined),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('快捷指令', style: theme.textTheme.labelMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (action, label, icon) in actions)
              _ActionButton(
                label: label,
                icon: icon,
                enabled: enabled,
                onPressed: () => onAction(action),
              ),
          ],
        ),
      ],
    );
  }
}

final class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 36,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: enabled
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: enabled
                        ? colorScheme.onSurface
                        : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 自定义指令输入 + 发送。
final class _CustomPromptSection extends StatelessWidget {
  const _CustomPromptSection({
    required this.controller,
    required this.busy,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('自定义指令', style: theme.textTheme.labelMedium),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          enabled: !busy,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: '例如：把这段改成更具悬念的口吻…',
            hintStyle: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: theme.colorScheme.primary),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonalIcon(
            onPressed: busy ? null : onSend,
            icon: const Icon(Icons.send_rounded, size: 16),
            label: const Text('发送'),
          ),
        ),
      ],
    );
  }
}

/// 请求进行中的指示。
final class _BusyIndicator extends StatelessWidget {
  const _BusyIndicator();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            '正在请求模型…',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 失败提示 + 重试。
final class _ErrorSection extends StatelessWidget {
  const _ErrorSection({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 16,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
                height: 1.4,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

/// 生成结果 + 应用回文档的动作行。
final class _ResultSection extends StatelessWidget {
  const _ResultSection({
    required this.text,
    required this.hasSelection,
    required this.documentOpen,
    required this.busy,
    required this.onApply,
    required this.onCopy,
    required this.onClear,
  });

  final String text;
  final bool hasSelection;
  final bool documentOpen;
  final bool busy;
  final void Function(AgentApplyTarget target) onApply;
  final VoidCallback onCopy;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('结果', style: theme.textTheme.labelMedium),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: SelectableText(
            text,
            style: theme.textTheme.bodySmall?.copyWith(height: 1.6),
          ),
        ),
        const SizedBox(height: 10),
        if (documentOpen)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ApplyButton(
                label: '替换选区',
                icon: Icons.find_replace_outlined,
                enabled: hasSelection && !busy,
                onPressed: () => onApply(AgentApplyTarget.replaceSelection),
              ),
              _ApplyButton(
                label: '插入到光标',
                icon: Icons.south_west_outlined,
                enabled: !busy,
                onPressed: () => onApply(AgentApplyTarget.insertAtCursor),
              ),
              _ApplyButton(
                label: '追加文末',
                icon: Icons.arrow_downward_rounded,
                enabled: !busy,
                onPressed: () => onApply(AgentApplyTarget.append),
              ),
            ],
          ),
        Row(
          children: [
            TextButton.icon(
              onPressed: busy ? null : onCopy,
              icon: const Icon(Icons.copy_rounded, size: 15),
              label: const Text('复制'),
            ),
            TextButton.icon(
              onPressed: busy ? null : onClear,
              icon: const Icon(Icons.close_rounded, size: 15),
              label: const Text('清空'),
            ),
          ],
        ),
      ],
    );
  }
}

final class _ApplyButton extends StatelessWidget {
  const _ApplyButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: enabled
          ? colorScheme.secondaryContainer.withValues(alpha: 0.6)
          : colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 34,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: enabled
                      ? colorScheme.onSecondaryContainer
                      : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: enabled
                        ? colorScheme.onSecondaryContainer
                        : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 配置加载失败（含测试环境平台通道不可用）时的错误视图。
final class _ConfigLoadErrorView extends StatelessWidget {
  const _ConfigLoadErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 30,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            Text(
              'AI 配置加载失败',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 未启用 / 未配置 API Key 时的引导视图。
final class _NotConfiguredView extends StatelessWidget {
  const _NotConfiguredView({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.auto_awesome, size: 26, color: colorScheme.primary),
            ),
            const SizedBox(height: 14),
            Text(
              '写作助手未启用',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '在设置中填写模型接口与 API Key 并启用后，即可对选中文字或当前章节'
              '执行校对、润色、总结与续写。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onOpenSettings,
              icon: const Icon(Icons.settings_outlined, size: 16),
              label: const Text('去设置'),
            ),
          ],
        ),
      ),
    );
  }
}
