import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_editor/lore_editor.dart';
import 'package:lore_ui/lore_ui.dart';
import 'package:path/path.dart' as p;

import '../preferences/settings_page.dart';
import '../workspace/chapter_navigation.dart';
import '../workspace/workspace_controller.dart';
import 'ai_providers.dart';
import 'linked_outline_context.dart';
import 'outline_generator_panel.dart';

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

  /// 当前结果是否允许应用回文档（一致性检查等清单型结果置 false）。
  bool _allowApplyResult = true;

  /// 当前小说已加载的 AI 请求缓存（null = 未加载）。
  AiCache? _cache;

  /// 已加载缓存对应的小说 id；build 里变化时重载。
  String? _cacheNovelId;

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  WorkspaceController get controller => widget.controller;

  OpenDocument? get _activeDocument => controller.activeDocument;

  Future<void> _loadCache(NovelSnapshot novel) async {
    try {
      final cache = await ref
          .read(aiCacheServiceProvider)
          .load(controller.session, novelRootPath: novel.rootPath);
      if (mounted && novel.metadata.id.value == _cacheNovelId) {
        setState(() => _cache = cache);
      }
    } catch (error, stackTrace) {
      debugPrint('ai cache load failed: $error\n$stackTrace');
    }
  }

  Future<void> _saveCache(NovelSnapshot novel) async {
    final cache = _cache;
    if (cache == null) {
      return;
    }
    try {
      await ref
          .read(aiCacheServiceProvider)
          .save(
            controller.session,
            novelRootPath: novel.rootPath,
            cache: cache,
          );
    } catch (error, stackTrace) {
      debugPrint('ai cache save failed: $error\n$stackTrace');
    }
  }

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
    final novel = controller.activeNovel;
    // 小说变化时重载该小说的 .cache 历史（同一小说不重复加载）。
    final novelId = novel?.metadata.id.value;
    if (novelId != _cacheNovelId) {
      _cacheNovelId = novelId;
      _cache = null;
      if (novel != null) {
        unawaited(_loadCache(novel));
      }
    }
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
        // 按小说 id 作 key：切换小说时重载大纲列表与关联状态。
        _OutlineSection(
          key: novel == null
              ? null
              : ValueKey('outline-section-${novel.metadata.id.value}'),
          controller: controller,
          novel: novel,
        ),
        const SizedBox(height: 14),
        // 按小说 id 作 key：切换小说时重载记忆状态。
        _MemorySection(
          key: novel == null
              ? null
              : ValueKey('memory-section-${novel.metadata.id.value}'),
          controller: controller,
          novel: novel,
        ),
        const SizedBox(height: 14),
        // 按小说 id 作 key：切换小说时重载设定记忆状态。
        _SettingMemorySection(
          key: novel == null
              ? null
              : ValueKey('setting-memory-section-${novel.metadata.id.value}'),
          controller: controller,
          novel: novel,
        ),
        const SizedBox(height: 14),
        _ActionSection(
          enabled: doc != null && !_busy,
          onAction: _runAction,
          outlineEnabled: !_busy,
          onGenerateOutline: () =>
              showOutlineGeneratorSheet(context, controller),
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
            allowApply: _allowApplyResult,
            onApply: (target) => _apply(doc!, target, _result!),
            onCopy: _copyResult,
            onClear: () => setState(() {
              _result = null;
              _error = null;
              // 一并清空自定义指令输入框，避免残留指令影响下一次请求。
              _promptController.clear();
            }),
          ),
        ],
        const SizedBox(height: 18),
        _CacheSection(
          loaded: _cache != null,
          entries: _cache?.entries ?? const [],
          documentOpen: doc != null,
          onUseInstruction: _useCachedInstruction,
          onRerun: _rerunCached,
          onApply: (text) =>
              _apply(doc!, AgentApplyTarget.replaceSelection, text),
          onDeleteEntry: (index) {
            if (novel != null) {
              unawaited(_deleteCacheEntry(novel, index));
            }
          },
          onClear: () {
            if (novel != null) {
              unawaited(_clearCache(novel));
            }
          },
        ),
      ],
    );
  }

  void _useCachedInstruction(String instruction) {
    _promptController.text = instruction;
    setState(() {});
  }

  void _rerunCached(AiCacheEntry entry) {
    if (entry.kind == AiCacheEntryKind.action) {
      final action = _actionFromName(entry.prompt);
      if (action != null) {
        _execute(action: action);
        return;
      }
    }
    _useCachedInstruction(entry.prompt);
  }

  Future<void> _deleteCacheEntry(NovelSnapshot novel, int index) async {
    final cache = _cache;
    if (cache == null) {
      return;
    }
    _cache = cache.removeAt(index);
    setState(() {});
    await _saveCache(novel);
  }

  Future<void> _clearCache(NovelSnapshot novel) async {
    _cache = const AiCache.empty();
    setState(() {});
    await _saveCache(novel);
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

  /// 读取当前小说已关联大纲的内容，合并成参考文本。实现见共享的
  /// [buildLinkedOutlineReference]，写作助手与大纲生成面板共用。
  Future<String> _linkedOutlineContext() {
    return buildLinkedOutlineReference(
      controller: controller,
      links: ref.read(linkedOutlinesProvider).value,
    );
  }

  /// 读取当前小说的章节记忆文档（`小说记忆.md`），不存在或读失败返回空串。
  Future<String> _readMemoryContext() async {
    final novel = controller.activeNovel;
    if (novel == null) {
      return '';
    }
    final path = p.join(novel.rootPath, '$chapterMemoryDocName.md');
    try {
      final snapshot = await controller.service.readDocument(
        controller.session,
        DocumentRef(relativePath: path, format: DocumentFormat.markdown),
      );
      return snapshot.text;
    } on LibraryOperationException {
      return '';
    }
  }

  /// 读取当前小说的设定记忆文档（`设定记忆.md`），不存在或读失败返回空串。
  Future<String> _readSettingMemoryContext() async {
    final novel = controller.activeNovel;
    if (novel == null) {
      return '';
    }
    final path = p.join(novel.rootPath, '$settingMemoryDocName.md');
    try {
      final snapshot = await controller.service.readDocument(
        controller.session,
        DocumentRef(relativePath: path, format: DocumentFormat.markdown),
      );
      return snapshot.text;
    } on LibraryOperationException {
      return '';
    }
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
    if (configState == null ||
        !configState.config.enabled ||
        !configState.hasApiKey) {
      setState(() {
        _error = 'AI 未启用或未设置 API Key，请先到设置中配置';
        _result = null;
      });
      return;
    }
    final contextInfo = _currentContext();
    final referenceText = await _linkedOutlineContext();
    final memoryText = await _readMemoryContext();
    final settingText = await _readSettingMemoryContext();
    // 一致性检查依赖记忆材料：章节记忆与设定记忆都没有时无法对照，先拦截。
    if (action == WritingAgentAction.consistencyCheck &&
        memoryText.trim().isEmpty &&
        settingText.trim().isEmpty) {
      setState(() {
        _error = '一致性检查需要章节记忆或设定记忆，请先生成';
        _result = null;
      });
      return;
    }
    // 主上下文与参考材料（大纲、章节记忆、设定记忆）都为空才拦截；仅关联了大纲或
    // 已有章节/设定记忆时也允许执行（如按记忆规划续写）。
    if (contextInfo.text.trim().isEmpty &&
        referenceText.trim().isEmpty &&
        memoryText.trim().isEmpty &&
        settingText.trim().isEmpty) {
      setState(() {
        _error = '没有可用的上下文：请先选中文字、打开文档、关联大纲或生成章节记忆';
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
          referenceText: referenceText,
          memoryText: memoryText,
          settingText: settingText,
          config: configState.config,
          apiKey: configState.config.apiKey,
          timeout: action == WritingAgentAction.consistencyCheck
              ? const Duration(seconds: 120)
              : const Duration(seconds: 60),
        );
      } else if (custom != null) {
        text = await service.runCustom(
          instruction: custom,
          contextText: contextInfo.text,
          referenceText: referenceText,
          memoryText: memoryText,
          settingText: settingText,
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
        _allowApplyResult = action != WritingAgentAction.consistencyCheck;
      });
      await _recordCacheEntry(action: action, custom: custom, output: text);
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

  /// 记录本次成功请求到当前小说的 .cache 历史（精简元信息 + 输出）。
  Future<void> _recordCacheEntry({
    WritingAgentAction? action,
    String? custom,
    required String output,
  }) async {
    final novel = controller.activeNovel;
    if (novel == null) {
      return;
    }
    final contextInfo = _currentContext();
    final links = ref.read(linkedOutlinesProvider).value;
    final outlineCount = links?.forNovel(novel.metadata.id.value).length ?? 0;
    final main = contextInfo.fromSelection
        ? '选中文字 · ${contextInfo.count} 字'
        : '当前章节正文 · ${contextInfo.count} 字';
    final entry = AiCacheEntry(
      timestampMillis: DateTime.now().millisecondsSinceEpoch,
      kind: action != null ? AiCacheEntryKind.action : AiCacheEntryKind.custom,
      prompt: action != null ? action.name : (custom ?? ''),
      contextSummary: outlineCount > 0 ? '$main + 大纲 $outlineCount 个' : main,
      output: output,
    );
    _cache = (_cache ?? const AiCache.empty()).append(entry);
    await _saveCache(novel);
  }

  void _apply(OpenDocument doc, AgentApplyTarget target, String text) {
    if (text.isEmpty) {
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
              ? editor.text.replaceRange(selection.start, selection.end, text)
              : editor.text + text,
          selection: TextSelection.collapsed(
            offset:
                (selection.isValid ? selection.start : editor.text.length) +
                text.length,
          ),
        ),
        AgentApplyTarget.append => TextEditingValue(
          text: '${editor.text}\n$text',
          selection: TextSelection.collapsed(
            offset: editor.text.length + 1 + text.length,
          ),
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
            final selected = hasSelection ? selection.end - selection.start : 0;
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

/// 关联大纲区块：列出当前小说 `大纲/` 下的 Markdown 文件，可多选；关联选择
/// 按小说持久化。生成请求时会把这些大纲内容作为参考上下文发给模型。
final class _OutlineSection extends ConsumerStatefulWidget {
  const _OutlineSection({
    required this.controller,
    required this.novel,
    super.key,
  });

  final WorkspaceController controller;

  /// 当前小说；null 表示没有可关联的小说。
  final NovelSnapshot? novel;

  @override
  ConsumerState<_OutlineSection> createState() => _OutlineSectionState();
}

final class _OutlineSectionState extends ConsumerState<_OutlineSection> {
  late final Future<List<LibraryEntry>> _outlineFuture = _loadOutlines();

  Future<List<LibraryEntry>> _loadOutlines() async {
    final novel = widget.novel;
    if (novel == null) {
      return const <LibraryEntry>[];
    }
    final dirPath = p.join(novel.rootPath, outlineDirectoryName);
    final entries = await widget.controller.listChildren(relativePath: dirPath);
    return entries
        .where((entry) => entry.type == LibraryEntryType.markdownFile)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final novel = widget.novel;
    if (novel == null) {
      return Text('未打开小说，无法关联大纲', style: muted);
    }
    final novelId = novel.metadata.id.value;
    final linked =
        ref.watch(linkedOutlinesProvider).value?.forNovel(novelId) ??
        const <String>[];
    final linkedSet = linked.toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('关联大纲', style: theme.textTheme.labelMedium),
        const SizedBox(height: 8),
        FutureBuilder<List<LibraryEntry>>(
          future: _outlineFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return Text('加载中…', style: muted);
            }
            if (snapshot.hasError) {
              return Text('大纲列表加载失败', style: muted);
            }
            final entries = snapshot.data ?? const <LibraryEntry>[];
            if (entries.isEmpty) {
              return Text('当前小说暂无大纲文件（可在结构面板「新建大纲」创建）', style: muted);
            }
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in entries)
                  _OutlineChip(
                    name: entry.name,
                    selected: linkedSet.contains(entry.relativePath),
                    onTap: () => _toggle(entry.relativePath),
                  ),
              ],
            );
          },
        ),
        if (linked.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            '将发送大纲：${linked.map((path) => p.basename(path)).join('、')}',
            style: muted,
          ),
        ],
      ],
    );
  }

  Future<void> _toggle(String path) async {
    final novel = widget.novel;
    if (novel == null) {
      return;
    }
    final controller = ref.read(linkedOutlinesProvider.notifier);
    final currentlyLinked =
        (ref
                    .read(linkedOutlinesProvider)
                    .value
                    ?.forNovel(novel.metadata.id.value) ??
                const <String>[])
            .contains(path);
    try {
      if (currentlyLinked) {
        await controller.unlink(novel.metadata.id.value, path);
      } else {
        await controller.link(novel.metadata.id.value, path);
      }
    } catch (_) {
      if (mounted) {
        LoreToast.error(context, '关联保存失败，请重试');
      }
    }
  }
}

/// 章节记忆区块：展示当前小说 `小说记忆.md` 的状态，提供生成/更新与打开入口。
///
/// 记忆文档由 AI 依据全部已写章节生成，注入写作请求时让输出与历史情节一致。
final class _MemorySection extends ConsumerStatefulWidget {
  const _MemorySection({
    required this.controller,
    required this.novel,
    super.key,
  });

  final WorkspaceController controller;

  /// 当前小说；null 表示没有可记忆的小说。
  final NovelSnapshot? novel;

  @override
  ConsumerState<_MemorySection> createState() => _MemorySectionState();
}

final class _MemorySectionState extends ConsumerState<_MemorySection> {
  late Future<_MemoryStatus> _statusFuture = _loadStatus();
  bool _busy = false;

  Future<_MemoryStatus> _loadStatus() async {
    final novel = widget.novel;
    if (novel == null) {
      return const _MemoryStatus(exists: false);
    }
    final chapters = _memoryChapterItems(novel);
    final chapterCount = chapters.length;
    final path = p.join(novel.rootPath, '$chapterMemoryDocName.md');
    final rootChildren = await widget.controller.listChildren(
      relativePath: novel.rootPath,
    );
    final entry = rootChildren
        .where(
          (entry) =>
              entry.type != LibraryEntryType.directory &&
              entry.relativePath == path,
        )
        .firstOrNull;
    if (entry == null) {
      return _MemoryStatus(
        exists: false,
        chapterCount: chapterCount,
        chapters: chapters,
      );
    }
    try {
      final snapshot = await widget.controller.service.readDocument(
        widget.controller.session,
        DocumentRef(relativePath: path, format: DocumentFormat.markdown),
      );
      final docEntries = parseMemoryEntries(snapshot.text);
      final docKeys = docEntries
          .map((entry) => entry.key)
          .whereType<MemoryKey>()
          .toSet();
      final coveredItems = [
        for (final item in chapters)
          _MemoryChapterItem(
            id: item.id,
            label: item.label,
            volumeLabel: item.volumeLabel,
            key: item.key,
            covered: docKeys.contains(item.key),
          ),
      ];
      final chapterKeys = chapters.map((item) => item.key).toSet();
      final orphanCount = docEntries
          .where((entry) {
            final key = entry.key;
            return key != null && !chapterKeys.contains(key);
          })
          .length;
      return _MemoryStatus(
        exists: true,
        memoryChapterCount: parseMemoryChapterCount(snapshot.text),
        chapterCount: chapterCount,
        chapters: coveredItems,
        missingCount: coveredItems.where((item) => !item.covered).length,
        orphanCount: orphanCount,
      );
    } on LibraryOperationException {
      return _MemoryStatus(
        exists: false,
        chapterCount: chapterCount,
        chapters: chapters,
      );
    }
  }

  Future<void> _generate() async {
    final novel = widget.novel;
    if (novel == null) {
      return;
    }
    final configState = ref.read(agentConfigProvider).value;
    if (configState == null ||
        !configState.config.enabled ||
        !configState.hasApiKey) {
      if (mounted) {
        LoreToast.error(context, 'AI 未启用或未设置 API Key，请先到设置中配置');
      }
      return;
    }
    setState(() => _busy = true);
    try {
      final text = await ref
          .read(memoryGenerationServiceProvider)
          .generateMemory(
            session: widget.controller.session,
            novel: novel,
            config: configState.config,
            apiKey: configState.config.apiKey,
          );
      await widget.controller.saveGeneratedMemory(
        novelId: novel.metadata.id,
        memoryText: text,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _statusFuture = _loadStatus();
      });
      LoreToast.success(context, '章节记忆已生成');
    } on AiRequestException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      LoreToast.error(context, error.message);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      LoreToast.error(context, '保存章节记忆失败：$error');
    }
  }

  Future<void> _open() async {
    final novel = widget.novel;
    if (novel == null) {
      return;
    }
    final path = p.join(novel.rootPath, '$chapterMemoryDocName.md');
    try {
      await widget.controller.openPath(path);
    } on LibraryOperationException {
      if (mounted) {
        LoreToast.error(context, '无法打开章节记忆');
      }
    }
  }

  /// 增量更新记忆：[chapterIds] 为空时只补缺失章节，非空时只更新指定章节。
  ///
  /// [asGenerate] 为真表示当前尚无记忆文档（初始「选择章节」生成），成功提示
  /// 用「已生成」而非「已更新」。
  Future<void> _updateMemory({
    Set<ContentId>? chapterIds,
    bool asGenerate = false,
  }) async {
    final novel = widget.novel;
    if (novel == null) {
      return;
    }
    final configState = ref.read(agentConfigProvider).value;
    if (configState == null ||
        !configState.config.enabled ||
        !configState.hasApiKey) {
      if (mounted) {
        LoreToast.error(context, 'AI 未启用或未设置 API Key，请先到设置中配置');
      }
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(memoryGenerationServiceProvider)
          .updateMemory(
            session: widget.controller.session,
            novel: novel,
            config: configState.config,
            apiKey: configState.config.apiKey,
            chapterIds: chapterIds,
          );
      await widget.controller.saveGeneratedMemory(
        novelId: novel.metadata.id,
        memoryText: result.text,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _statusFuture = _loadStatus();
      });
      if (result.updatedChapters.isEmpty) {
        LoreToast.show(
          context,
          message: '所选章节已在记忆中',
          type: LoreToastType.info,
        );
      } else if (result.rebuilt) {
        LoreToast.success(context, '检测到编号冲突或旧格式，已整篇重建记忆');
      } else if (asGenerate) {
        LoreToast.success(context, '章节记忆已生成');
      } else {
        LoreToast.success(context, '章节记忆已更新');
      }
    } on AiRequestException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      LoreToast.error(context, error.message);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      LoreToast.error(context, '保存章节记忆失败：$error');
    }
  }

  Future<void> _showChapterPicker(_MemoryStatus status) async {
    final novel = widget.novel;
    if (novel == null || status.chapters.isEmpty) {
      return;
    }
    final selected = await showDialog<Set<ContentId>>(
      context: context,
      builder: (context) => _MemoryChapterPickerDialog(
        chapters: status.chapters,
        initiallySelected: {
          for (final item in status.chapters)
            if (!item.covered) item.id,
        },
      ),
    );
    if (selected == null || selected.isEmpty) {
      return;
    }
    await _updateMemory(chapterIds: selected, asGenerate: !status.exists);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final novel = widget.novel;
    if (novel == null) {
      return Text('未打开小说，无法生成章节记忆', style: muted);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('章节记忆', style: theme.textTheme.labelMedium),
        const SizedBox(height: 8),
        FutureBuilder<_MemoryStatus>(
          future: _statusFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return Text('加载中…', style: muted);
            }
            final status =
                snapshot.data ?? const _MemoryStatus(exists: false);
            if (_busy) {
              return const _BusyIndicator();
            }
            if (!status.exists) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('尚未生成章节记忆：AI 将无法参考已写章节', style: muted),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _generate,
                        icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                        label: const Text('生成记忆'),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () => _showChapterPicker(status),
                        icon: const Icon(
                          Icons.playlist_add_check_rounded,
                          size: 16,
                        ),
                        label: const Text('选择章节…'),
                      ),
                    ],
                  ),
                ],
              );
            }
            final missing = status.missingCount;
            final stale = missing > 0;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.memoryChapterCount == null
                      ? '章节记忆已生成'
                      : '已基于 ${status.memoryChapterCount} 章生成',
                  style: muted,
                ),
                if (stale) ...[
                  const SizedBox(height: 4),
                  Text(
                    '当前 ${status.chapterCount} 章，$missing 章尚未在记忆中，建议更新',
                    style: muted?.copyWith(color: theme.colorScheme.error),
                  ),
                ],
                if (status.orphanCount > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${status.orphanCount} 条记忆对应章节已不存在（可能被移动/删除），可在「全部重新生成」清理',
                    style: muted?.copyWith(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: missing > 0
                          ? () => _updateMemory()
                          : () => _showChapterPicker(status),
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('更新记忆'),
                    ),
                    TextButton.icon(
                      onPressed: () => _showChapterPicker(status),
                      icon: const Icon(Icons.playlist_add_check_rounded, size: 16),
                      label: const Text('选择章节…'),
                    ),
                    TextButton.icon(
                      onPressed: _open,
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('打开'),
                    ),
                    PopupMenuButton<String>(
                      tooltip: '更多',
                      onSelected: (value) {
                        if (value == 'rebuild') {
                          _generate();
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'rebuild',
                          child: Text('全部重新生成'),
                        ),
                      ],
                      icon: const Icon(Icons.more_horiz_rounded, size: 18),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// 设定记忆区块：展示当前小说 `设定记忆.md` 的状态，提供生成与打开入口。
///
/// 设定记忆由 AI 依据章节记忆二次提炼（人物/地点/时间线/伏笔结构化设定），
/// v1 只做整篇重建，供一致性检查与续写参考。
final class _SettingMemorySection extends ConsumerStatefulWidget {
  const _SettingMemorySection({
    required this.controller,
    required this.novel,
    super.key,
  });

  final WorkspaceController controller;

  /// 当前小说；null 表示没有可记忆的小说。
  final NovelSnapshot? novel;

  @override
  ConsumerState<_SettingMemorySection> createState() =>
      _SettingMemorySectionState();
}

final class _SettingMemorySectionState
    extends ConsumerState<_SettingMemorySection> {
  late Future<_SettingMemoryStatus> _statusFuture = _loadStatus();
  bool _busy = false;

  Future<_SettingMemoryStatus> _loadStatus() async {
    final novel = widget.novel;
    if (novel == null) {
      return const _SettingMemoryStatus(exists: false);
    }
    final path = p.join(novel.rootPath, '$settingMemoryDocName.md');
    final rootChildren = await widget.controller.listChildren(
      relativePath: novel.rootPath,
    );
    final entry = rootChildren
        .where(
          (entry) =>
              entry.type != LibraryEntryType.directory &&
              entry.relativePath == path,
        )
        .firstOrNull;
    if (entry == null) {
      return const _SettingMemoryStatus(exists: false);
    }
    try {
      final snapshot = await widget.controller.service.readDocument(
        widget.controller.session,
        DocumentRef(relativePath: path, format: DocumentFormat.markdown),
      );
      return _SettingMemoryStatus(
        exists: true,
        counts: parseSettingMemoryCounts(snapshot.text),
      );
    } on LibraryOperationException {
      return const _SettingMemoryStatus(exists: false);
    }
  }

  Future<void> _generate() async {
    final novel = widget.novel;
    if (novel == null) {
      return;
    }
    final configState = ref.read(agentConfigProvider).value;
    if (configState == null ||
        !configState.config.enabled ||
        !configState.hasApiKey) {
      if (mounted) {
        LoreToast.error(context, 'AI 未启用或未设置 API Key，请先到设置中配置');
      }
      return;
    }
    setState(() => _busy = true);
    try {
      final text = await ref
          .read(settingMemoryGenerationServiceProvider)
          .generateSettingMemory(
            session: widget.controller.session,
            novel: novel,
            config: configState.config,
            apiKey: configState.config.apiKey,
          );
      await widget.controller.saveGeneratedMemory(
        novelId: novel.metadata.id,
        memoryText: text,
        docName: settingMemoryDocName,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _statusFuture = _loadStatus();
      });
      LoreToast.success(context, '设定记忆已生成');
    } on AiRequestException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      LoreToast.error(context, error.message);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      LoreToast.error(context, '保存设定记忆失败：$error');
    }
  }

  Future<void> _open() async {
    final novel = widget.novel;
    if (novel == null) {
      return;
    }
    final path = p.join(novel.rootPath, '$settingMemoryDocName.md');
    try {
      await widget.controller.openPath(path);
    } on LibraryOperationException {
      if (mounted) {
        LoreToast.error(context, '无法打开设定记忆');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final novel = widget.novel;
    if (novel == null) {
      return Text('未打开小说，无法生成设定记忆', style: muted);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('设定记忆', style: theme.textTheme.labelMedium),
        const SizedBox(height: 8),
        FutureBuilder<_SettingMemoryStatus>(
          future: _statusFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return Text('加载中…', style: muted);
            }
            final status =
                snapshot.data ?? const _SettingMemoryStatus(exists: false);
            if (_busy) {
              return const _BusyIndicator();
            }
            if (!status.exists) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('尚未生成设定记忆：AI 将无法核对设定一致性', style: muted),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: _generate,
                    icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                    label: const Text('生成设定记忆'),
                  ),
                ],
              );
            }
            final counts = status.counts;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '人物 ${counts.characters} · 地点 ${counts.locations} · '
                  '时间线 ${counts.timeline} · 伏笔 ${counts.foreshadowing}',
                  style: muted,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _generate,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('重新生成'),
                    ),
                    TextButton.icon(
                      onPressed: _open,
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('打开'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// 设定记忆区块状态：文档是否存在 + 四类条目计数。
final class _SettingMemoryStatus {
  const _SettingMemoryStatus({
    required this.exists,
    this.counts = const SettingMemoryCounts(),
  });

  final bool exists;
  final SettingMemoryCounts counts;
}

/// 章节记忆状态：文件是否存在、记忆基于的章节数、当前章节及其覆盖情况。
final class _MemoryStatus {
  const _MemoryStatus({
    required this.exists,
    this.memoryChapterCount,
    this.chapterCount = 0,
    this.chapters = const [],
    this.missingCount = 0,
    this.orphanCount = 0,
  });

  final bool exists;
  final int? memoryChapterCount;
  final int chapterCount;
  final List<_MemoryChapterItem> chapters;
  final int missingCount;
  final int orphanCount;
}

/// 单章记忆覆盖状态（阅读序、按卷分组），供「选择章节」对话框使用。
final class _MemoryChapterItem {
  const _MemoryChapterItem({
    required this.id,
    required this.label,
    required this.volumeLabel,
    required this.key,
    required this.covered,
  });

  final ContentId id;
  final String label;
  final String? volumeLabel;
  final MemoryKey key;
  final bool covered;
}

/// 按阅读序枚举当前小说的可记忆章节（跳过空章），纯元数据零额外 IO。
List<_MemoryChapterItem> _memoryChapterItems(NovelSnapshot novel) {
  final tree = novel.contentTree;
  final mode = novel.metadata.numberingMode;
  return [
    for (final node in chaptersInReadingOrder(novel))
      if (node.characterCount != 0)
        _MemoryChapterItem(
          id: node.id,
          label: _memoryChapterLabel(node, mode: mode, tree: tree),
          volumeLabel: _volumeLabelOf(node, tree),
          key: memoryKeyForNode(node: node, mode: mode, tree: tree),
          covered: false,
        ),
  ];
}

/// 章节条目展示名（纯元数据，不带副标题）：`第3章` / `第1卷 第3章` / `未分卷 第3章` / `序章`。
String _memoryChapterLabel(
  ContentNode node, {
  required NumberingMode mode,
  required ContentTree tree,
}) {
  final number = node.number;
  if (number == null) {
    return p.basenameWithoutExtension(node.relativePath);
  }
  if (mode != NumberingMode.perVolume) {
    return '第$number章';
  }
  final volume = _volumeNumber(node, tree);
  return volume == null ? '未分卷 第$number章' : '第$volume卷 第$number章';
}

/// 章节所在卷号；父节点非卷或卷号缺失时返回 null（按「正文根级」分组）。
int? _volumeNumber(ContentNode node, ContentTree tree) {
  final parent = tree.nodeById(node.parentId);
  if (parent == null || parent.type != ContentNodeType.volume) {
    return null;
  }
  return parent.number;
}

/// 卷分组名：有卷号的目录用「第V卷」，否则用目录名。
String? _volumeLabelOf(ContentNode node, ContentTree tree) {
  final parent = tree.nodeById(node.parentId);
  if (parent == null || parent.type != ContentNodeType.volume) {
    return null;
  }
  final number = parent.number;
  if (number != null) {
    return '第$number卷';
  }
  return p.basenameWithoutExtension(parent.relativePath);
}

/// 「选择要更新的章节」对话框：按卷分组的多选列表，默认勾选缺失章节。
final class _MemoryChapterPickerDialog extends StatefulWidget {
  const _MemoryChapterPickerDialog({
    required this.chapters,
    required this.initiallySelected,
  });

  final List<_MemoryChapterItem> chapters;
  final Set<ContentId> initiallySelected;

  @override
  State<_MemoryChapterPickerDialog> createState() =>
      _MemoryChapterPickerDialogState();
}

final class _MemoryChapterPickerDialogState
    extends State<_MemoryChapterPickerDialog> {
  late final Set<ContentId> _selected = {...widget.initiallySelected};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final groups = <String?, List<_MemoryChapterItem>>{};
    for (final item in widget.chapters) {
      groups.putIfAbsent(item.volumeLabel, () => []).add(item);
    }
    return AlertDialog(
      title: const Text('选择要更新的章节'),
      content: SizedBox(
        width: 420,
        height: 380,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TextButton(
                  onPressed: () => setState(
                    () => _selected.addAll(
                      widget.chapters.map((item) => item.id),
                    ),
                  ),
                  child: const Text('全选'),
                ),
                TextButton(
                  onPressed: () => setState(_selected.clear),
                  child: const Text('清空'),
                ),
                const Spacer(),
                Text('默认勾选未生成章节', style: muted),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: ListView(
                children: [
                  for (final group in groups.entries) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                      child: Text(
                        group.key ?? '正文',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    for (final item in group.value)
                      CheckboxListTile(
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _selected.contains(item.id),
                        onChanged: (value) => setState(() {
                          if (value == true) {
                            _selected.add(item.id);
                          } else {
                            _selected.remove(item.id);
                          }
                        }),
                        title: Text(
                          item.label,
                          style: theme.textTheme.bodyMedium,
                        ),
                        subtitle: item.covered
                            ? null
                            : Text(
                                '尚未生成',
                                style: muted?.copyWith(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

final class _OutlineChip extends StatelessWidget {
  const _OutlineChip({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(
                  Icons.check_rounded,
                  size: 14,
                  color: colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                name,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: selected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurface,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
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
    required this.outlineEnabled,
    required this.onGenerateOutline,
  });

  final bool enabled;
  final ValueChanged<WritingAgentAction> onAction;

  /// 「生成大纲」独立可用：不要求打开文档，只要求 AI 已配置。
  final bool outlineEnabled;
  final VoidCallback onGenerateOutline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actions = const [
      (WritingAgentAction.proofread, '校对', Icons.spellcheck_outlined),
      (WritingAgentAction.polish, '润色', Icons.auto_awesome_outlined),
      (WritingAgentAction.summarize, '总结', Icons.compress_outlined),
      (WritingAgentAction.continueWriting, '续写', Icons.edit_note_outlined),
      (
        WritingAgentAction.consistencyCheck,
        '一致性检查',
        Icons.rule_outlined,
      ),
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
            _ActionButton(
              label: '生成大纲',
              icon: Icons.account_tree_outlined,
              enabled: outlineEnabled,
              onPressed: onGenerateOutline,
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
    this.allowApply = true,
    required this.onApply,
    required this.onCopy,
    required this.onClear,
  });

  final String text;
  final bool hasSelection;
  final bool documentOpen;
  final bool busy;

  /// 清单型结果（如一致性检查）置 false 时隐藏应用按钮。
  final bool allowApply;
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
        if (documentOpen && allowApply)
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
                Icons.auto_awesome,
                size: 26,
                color: colorScheme.primary,
              ),
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
              '执行校对、润色、总结、续写与一致性检查。',
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

/// 预置动作的中文显示名。
String _actionLabel(WritingAgentAction action) => switch (action) {
  WritingAgentAction.proofread => '校对',
  WritingAgentAction.polish => '润色',
  WritingAgentAction.summarize => '总结',
  WritingAgentAction.continueWriting => '续写',
  WritingAgentAction.consistencyCheck => '一致性检查',
};

WritingAgentAction? _actionFromName(String name) {
  for (final action in WritingAgentAction.values) {
    if (action.name == name) {
      return action;
    }
  }
  return null;
}

/// 缓存条目在历史列表里的显示标题（动作名或截断的自定义指令）。
String _cacheEntryLabel(AiCacheEntry entry) {
  if (entry.kind == AiCacheEntryKind.action) {
    final action = _actionFromName(entry.prompt);
    if (action != null) {
      return _actionLabel(action);
    }
  }
  final text = entry.prompt.trim();
  return text.length <= 16 ? text : '${text.substring(0, 16)}…';
}

String _cacheEntryTime(int timestampMillis) {
  final time = DateTime.fromMillisecondsSinceEpoch(timestampMillis);
  final now = DateTime.now();
  final local = time.toLocal();
  final sameDay =
      now.year == local.year &&
      now.month == local.month &&
      now.day == local.day;
  String two(int n) => n.toString().padLeft(2, '0');
  final hm = '${two(local.hour)}:${two(local.minute)}';
  if (sameDay) {
    return hm;
  }
  return '${local.month}/${local.day} $hm';
}

/// AI 请求历史记录区块：查看、重跑/用指令、应用结果、删除与清空。
///
/// 数据由面板状态持有并落盘到小说目录 `.cache`；本组件纯展示 + 回调，内部
/// 只维护「哪条展开」的局部状态。
final class _CacheSection extends ConsumerStatefulWidget {
  const _CacheSection({
    required this.loaded,
    required this.entries,
    required this.documentOpen,
    required this.onUseInstruction,
    required this.onRerun,
    required this.onApply,
    required this.onDeleteEntry,
    required this.onClear,
  });

  final bool loaded;
  final List<AiCacheEntry> entries;
  final bool documentOpen;
  final void Function(String instruction) onUseInstruction;
  final void Function(AiCacheEntry entry) onRerun;
  final void Function(String output) onApply;
  final void Function(int index) onDeleteEntry;
  final VoidCallback onClear;

  @override
  ConsumerState<_CacheSection> createState() => _CacheSectionState();
}

final class _CacheSectionState extends ConsumerState<_CacheSection> {
  final Set<int> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final entries = widget.entries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('历史记录', style: theme.textTheme.labelMedium),
            const SizedBox(width: 6),
            if (entries.isNotEmpty)
              Text(
                '${entries.length}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const Spacer(),
            if (entries.isNotEmpty)
              TextButton(onPressed: widget.onClear, child: const Text('清空缓存')),
          ],
        ),
        const SizedBox(height: 6),
        if (!widget.loaded)
          Text('加载中…', style: muted)
        else if (entries.isEmpty)
          Text('暂无记录（每次请求自动保存到作品目录 .cache）', style: muted)
        else
          for (var i = entries.length - 1; i >= 0; i--)
            _CacheEntryCard(
              entry: entries[i],
              expanded: _expanded.contains(i),
              documentOpen: widget.documentOpen,
              onToggle: () => setState(() {
                if (!_expanded.add(i)) {
                  _expanded.remove(i);
                }
              }),
              onUseInstruction: widget.onUseInstruction,
              onRerun: () => widget.onRerun(entries[i]),
              onApply: () => widget.onApply(entries[i].output),
              onDelete: () => widget.onDeleteEntry(i),
            ),
      ],
    );
  }
}

final class _CacheEntryCard extends StatelessWidget {
  const _CacheEntryCard({
    required this.entry,
    required this.expanded,
    required this.documentOpen,
    required this.onToggle,
    required this.onUseInstruction,
    required this.onRerun,
    required this.onApply,
    required this.onDelete,
  });

  final AiCacheEntry entry;
  final bool expanded;
  final bool documentOpen;
  final VoidCallback onToggle;
  final void Function(String instruction) onUseInstruction;
  final VoidCallback onRerun;
  final VoidCallback onApply;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // 一致性检查输出为矛盾清单，不应应用回正文（连同历史记录里的该条）。
    final isConsistencyCheck =
        entry.kind == AiCacheEntryKind.action &&
        _actionFromName(entry.prompt) == WritingAgentAction.consistencyCheck;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      entry.kind == AiCacheEntryKind.action
                          ? Icons.auto_awesome_outlined
                          : Icons.chat_outlined,
                      size: 15,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _cacheEntryLabel(entry),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      _cacheEntryTime(entry.timestampMillis),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            if (expanded) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '上下文：${entry.contextSummary}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.5,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: SelectableText(
                        entry.output,
                        style: theme.textTheme.bodySmall?.copyWith(height: 1.6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (entry.kind == AiCacheEntryKind.action)
                          TextButton(
                            onPressed: onRerun,
                            child: const Text('重跑'),
                          )
                        else
                          TextButton(
                            onPressed: () => onUseInstruction(entry.prompt),
                            child: const Text('用此指令'),
                          ),
                        if (documentOpen && !isConsistencyCheck)
                          TextButton(
                            onPressed: onApply,
                            child: const Text('应用结果'),
                          ),
                        TextButton(
                          onPressed: onDelete,
                          child: const Text('删除'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
