import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_ui/lore_ui.dart';

import '../preferences/settings_page.dart';
import '../workspace/workspace_controller.dart';
import 'ai_providers.dart';
import 'linked_outline_context.dart';

/// 以辅助面板弹层打开「AI 生成大纲」（窄屏自动降级为 bottom sheet）。
///
/// [novelId] 可选：显式指定目标小说（结构面板传入当前小说）；缺省时回落到
/// [WorkspaceController.selectedNovel] / [activeNovel]。
Future<void> showOutlineGeneratorSheet(
  BuildContext context,
  WorkspaceController controller, {
  NovelId? novelId,
}) {
  return showLorePanelSheet<void>(
    context: context,
    title: 'AI 生成大纲',
    icon: Icons.account_tree_outlined,
    maxWidth: 600,
    child: OutlineGeneratorPanel(controller: controller, novelId: novelId),
  );
}

/// AI 大纲生成面板：按提示填写主题/世界背景/人物设定/卷/章设定，分两步生成完整
/// 大纲，并自动分类保存到 `世界观/`、`人物/`、`大纲/`，卷章大纲文件自动关联。
final class OutlineGeneratorPanel extends ConsumerStatefulWidget {
  const OutlineGeneratorPanel({
    required this.controller,
    this.novelId,
    super.key,
  });

  final WorkspaceController controller;
  final NovelId? novelId;

  @override
  ConsumerState<OutlineGeneratorPanel> createState() =>
      _OutlineGeneratorPanelState();
}

final class _OutlineGeneratorPanelState
    extends ConsumerState<OutlineGeneratorPanel> {
  final TextEditingController _themeController = TextEditingController();
  final TextEditingController _worldController = TextEditingController();
  final TextEditingController _characterController = TextEditingController();
  final TextEditingController _volumeController = TextEditingController();
  final TextEditingController _chapterController = TextEditingController();
  final TextEditingController _extraController = TextEditingController();

  NovelLength _novelLength = NovelLength.mediumLong;

  bool _busy = false;
  String _stepText = '';
  String? _error;
  String? _savedPath;

  @override
  void dispose() {
    _themeController.dispose();
    _worldController.dispose();
    _characterController.dispose();
    _volumeController.dispose();
    _chapterController.dispose();
    _extraController.dispose();
    super.dispose();
  }

  WorkspaceController get controller => widget.controller;

  /// 目标小说：显式传入 > 当前选中 > 当前活动文档所属。
  NovelId? get _targetNovelId =>
      widget.novelId ??
      controller.selectedNovel?.metadata.id ??
      controller.activeNovel?.metadata.id;

  void _openSettings() {
    showSettingsPanel(context, initialSection: 'ai');
  }

  @override
  Widget build(BuildContext context) {
    final agentAsync = ref.watch(agentConfigProvider);
    final configState = agentAsync.value;
    if (agentAsync.hasError) {
      return _ConfigErrorView(
        onRetry: () => ref.invalidate(agentConfigProvider),
      );
    }
    if (configState == null) {
      // 静态占位而非无限转圈：配置为本地快速读取。
      return const Center(child: Text('正在加载 AI 配置…'));
    }
    if (!configState.config.enabled || !configState.hasApiKey) {
      return _NotConfiguredView(onOpenSettings: _openSettings);
    }
    return _buildForm(context);
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    final linked = ref.watch(linkedOutlinesProvider).value;
    final novelId = _targetNovelId?.value;
    final linkedCount = novelId == null
        ? 0
        : (linked?.forNovel(novelId).length ?? 0);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _OutlineField(
          label: '主题 / 书名',
          controller: _themeController,
          hint: '例如：龙渊纪元',
          required: true,
          enabled: !_busy,
        ),
        const SizedBox(height: 12),
        Text(
          '小说长度',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<NovelLength>(
          initialValue: _novelLength,
          isExpanded: true,
          decoration: InputDecoration(
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
          items: [
            for (final length in NovelLength.values)
              DropdownMenuItem(value: length, child: Text(length.label)),
          ],
          onChanged: _busy
              ? null
              : (value) {
                  if (value != null) {
                    setState(() => _novelLength = value);
                  }
                },
        ),
        const SizedBox(height: 12),
        _OutlineField(
          label: '世界背景',
          controller: _worldController,
          hint: '例如：东方玄幻，灵气复苏；王朝与宗门并立…（留空由 AI 自行构思）',
          minLines: 3,
          maxLines: 5,
          enabled: !_busy,
        ),
        const SizedBox(height: 12),
        _OutlineField(
          label: '人物设定',
          controller: _characterController,
          hint: '例如：主角林晚，孤僻天才；反派为当朝丞相…（留空由 AI 自行构思）',
          minLines: 3,
          maxLines: 5,
          enabled: !_busy,
        ),
        const SizedBox(height: 12),
        _OutlineField(
          label: '卷设定',
          controller: _volumeController,
          hint: '例如：5 卷；或逐卷名称',
          enabled: !_busy,
        ),
        const SizedBox(height: 12),
        _OutlineField(
          label: '章设定',
          controller: _chapterController,
          hint: '例如：每卷 8-12 章；第 1 章作开篇',
          enabled: !_busy,
        ),
        const SizedBox(height: 12),
        _OutlineField(
          label: '补充要求',
          controller: _extraController,
          hint: '其他创作约束或风格提示（可选）',
          minLines: 2,
          maxLines: 4,
          enabled: !_busy,
        ),
        const SizedBox(height: 10),
        Text(
          linkedCount > 0
              ? '生成时将参考已关联的 $linkedCount 份大纲（仅作设定与风格参考）'
              : '未关联大纲；可先在「AI 写作助手」中关联已有大纲作为参考',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        if (_busy) _GenerationProgress(text: _stepText),
        if (_error != null) ...[
          const SizedBox(height: 8),
          _InlineError(message: _error!, onRetry: _busy ? null : _generate),
        ],
        if (_savedPath != null) ...[
          const SizedBox(height: 12),
          _SavedResult(
            path: _savedPath!,
            onDone: () => Navigator.of(context).maybePop(),
          ),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            style: loreDialogPrimaryButton(theme.colorScheme),
            onPressed: _busy ? null : _generate,
            icon: const Icon(Icons.auto_awesome_rounded, size: 16),
            label: const Text('生成大纲'),
          ),
        ),
      ],
    );
  }

  Future<void> _generate() async {
    final theme = _themeController.text.trim();
    if (theme.isEmpty) {
      setState(() => _error = '请先填写主题 / 书名');
      return;
    }
    final configState = ref.read(agentConfigProvider).value;
    if (configState == null ||
        !configState.config.enabled ||
        !configState.hasApiKey) {
      setState(() => _error = 'AI 未启用或未设置 API Key，请先到设置中配置');
      return;
    }
    final novelId = _targetNovelId;
    if (novelId == null) {
      setState(() => _error = '没有可保存的小说：请先打开或选择一部小说');
      return;
    }

    final request = OutlineGenerationRequest(
      theme: theme,
      novelLength: _novelLength,
      worldSetting: _worldController.text,
      characterSetting: _characterController.text,
      volumeSetting: _volumeController.text,
      chapterSetting: _chapterController.text,
      extraPrompt: _extraController.text,
    );

    setState(() {
      _busy = true;
      _error = null;
      _savedPath = null;
      _stepText = '① 正在生成世界观与人物设定…';
    });

    try {
      final referenceText = await buildLinkedOutlineReference(
        controller: controller,
        links: ref.read(linkedOutlinesProvider).value,
      );
      if (!mounted) {
        return;
      }
      setState(() => _stepText = '② 正在生成卷章大纲…');
      final outline = await ref
          .read(outlineGenerationServiceProvider)
          .generate(
            request: request,
            referenceText: referenceText,
            config: configState.config,
            apiKey: configState.config.apiKey,
          );
      if (!mounted) {
        return;
      }
      setState(() => _stepText = '正在分类保存…');
      final entry = await controller.saveGeneratedOutline(
        novelId: novelId,
        outline: outline,
        stem: theme,
      );
      await ref
          .read(linkedOutlinesProvider.notifier)
          .link(novelId.value, entry.relativePath);
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _stepText = '';
        _savedPath = entry.relativePath;
      });
      LoreToast.success(context, '大纲已生成并保存');
    } on AiRequestException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _stepText = '';
        _error = error.message;
      });
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _stepText = '';
        _error = '保存大纲失败：$error';
      });
    }
  }
}

/// 单个表单字段：标签 + 输入框（样式与写作助手的自定义指令输入一致）。
final class _OutlineField extends StatelessWidget {
  const _OutlineField({
    required this.label,
    required this.controller,
    this.hint,
    this.minLines = 1,
    this.maxLines = 3,
    this.enabled = true,
    this.required = false,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final int minLines;
  final int maxLines;
  final bool enabled;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          required ? '$label *' : label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          enabled: enabled,
          minLines: minLines,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
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
      ],
    );
  }
}

/// 两步生成进度。
final class _GenerationProgress extends StatelessWidget {
  const _GenerationProgress({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 失败提示 + 重试。
final class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

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
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

/// 生成成功：展示已保存的卷章大纲路径。
final class _SavedResult extends StatelessWidget {
  const _SavedResult({required this.path, required this.onDone});

  final String path;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 18,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('大纲已生成并保存', style: theme.textTheme.labelMedium),
                const SizedBox(height: 2),
                Text(
                  path,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onDone, child: const Text('完成')),
        ],
      ),
    );
  }
}

/// 配置加载失败（含测试环境平台通道不可用）时的错误视图。
final class _ConfigErrorView extends StatelessWidget {
  const _ConfigErrorView({required this.onRetry});

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
            Text('AI 配置加载失败', style: theme.textTheme.titleSmall),
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
              child: Icon(
                Icons.account_tree_outlined,
                size: 26,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'AI 生成大纲未启用',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '在设置中填写模型接口与 API Key 并启用后，即可按主题、世界背景、'
              '人物设定与卷章设定生成完整大纲，并自动分类保存。',
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
