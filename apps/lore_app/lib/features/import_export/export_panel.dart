import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';

import '../workspace/library_failure_snackbar.dart';
import '../workspace/workspace_controller.dart';
import 'workspace_export_access.dart';

/// 导出面板入口：加载小说快照后弹出选择面板。
///
/// [volumeId] 非空时只允许导出该卷内的章节（卷右键场景），否则可导出全部
/// 卷与章节（小说/正文右键场景）。
Future<void> showExportPanel({
  required BuildContext context,
  required WorkspaceController controller,
  required NovelId novelId,
  ContentId? volumeId,
}) async {
  NovelSnapshot snapshot;
  try {
    snapshot = await controller.loadNovelSnapshot(novelId);
  } on LibraryOperationException catch (error) {
    if (!context.mounted) {
      return;
    }
    showLibraryFailure(context, error.failure);
    return;
  }
  if (!context.mounted) {
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => ExportPanel(
      controller: controller,
      snapshot: snapshot,
      restrictVolumeId: volumeId,
    ),
  );
}

/// 一个卷/根下的可导出章节分组。
class _ExportGroup {
  const _ExportGroup({
    required this.key,
    required this.label,
    required this.chapters,
  });

  /// 展开收起状态用的稳定标识（卷 id 或根分组占位符）。
  final String key;
  final String label;
  final List<ContentNode> chapters;
}

class ExportPanel extends StatefulWidget {
  const ExportPanel({
    required this.controller,
    required this.snapshot,
    required this.restrictVolumeId,
    this.revealInFinder = _revealInFinderDefault,
    super.key,
  });

  final WorkspaceController controller;
  final NovelSnapshot snapshot;
  final ContentId? restrictVolumeId;

  /// 导出成功后在宿主平台定位产出文件（macOS 走 `open -R`）。可注入以便
  /// 单测替换，避免跑测试时真的派生 Finder 进程。
  final Future<void> Function(String path) revealInFinder;

  @override
  State<ExportPanel> createState() => _ExportPanelState();
}

/// 默认的 Finder 定位实现：仅 macOS 调 `open -R`，失败非致命。
Future<void> _revealInFinderDefault(String path) async {
  if (Platform.isMacOS) {
    try {
      await Process.run('open', ['-R', path]);
    } catch (_) {
      // 忽略：定位失败不影响已完成的导出。
    }
  }
}

class _ExportPanelState extends State<ExportPanel> {
  late final List<_ExportGroup> _groups;
  final Set<String> _selected = <String>{};
  // 收起的分组 key 集合；空集 = 全部展开（与旧版默认一致）。
  final Set<String> _collapsed = <String>{};
  final TextEditingController _fileNameController = TextEditingController();
  bool _includeTitles = true;
  bool _blankLineBetween = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _groups = _buildGroups();
    // 默认全选。
    for (final group in _groups) {
      for (final chapter in group.chapters) {
        _selected.add(chapter.id.value);
      }
    }
    final base = widget.snapshot.metadata.title;
    _fileNameController.text = base.isEmpty ? '导出小说.txt' : '$base.txt';
  }

  @override
  void dispose() {
    _fileNameController.dispose();
    super.dispose();
  }

  List<_ExportGroup> _buildGroups() {
    final tree = widget.snapshot.contentTree;
    final bodyId = widget.snapshot.metadata.body.id;
    final restrict = widget.restrictVolumeId;
    if (restrict != null) {
      final volume = tree.nodeById(restrict);
      final label = volume == null ? '卷' : _volumeLabel(volume);
      return [
        _ExportGroup(
          key: restrict.value,
          label: label,
          chapters: tree
              .childrenOf(restrict)
              .where((node) => node.type == ContentNodeType.chapter)
              .toList(),
        ),
      ];
    }
    final groups = <_ExportGroup>[];
    final rootChapters =
        tree.nodes
            .where(
              (node) =>
                  node.type == ContentNodeType.chapter &&
                  node.parentId == bodyId,
            )
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    if (rootChapters.isNotEmpty) {
      groups.add(
        _ExportGroup(key: '_body', label: '正文', chapters: rootChapters),
      );
    }
    final volumes =
        tree.nodes.where((node) => node.type == ContentNodeType.volume).toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    for (final volume in volumes) {
      final chapters = tree
          .childrenOf(volume.id)
          .where((node) => node.type == ContentNodeType.chapter)
          .toList();
      if (chapters.isNotEmpty) {
        groups.add(
          _ExportGroup(
            key: volume.id.value,
            label: _volumeLabel(volume),
            chapters: chapters,
          ),
        );
      }
    }
    return groups;
  }

  List<String> get _allIds => [
    for (final group in _groups)
      for (final c in group.chapters) c.id.value,
  ];

  bool get _allSelected {
    final ids = _allIds;
    return ids.isNotEmpty && ids.every(_selected.contains);
  }

  void _toggleAll(bool? value) {
    setState(() {
      if (value == true) {
        _selected.addAll(_allIds);
      } else {
        _selected.clear();
      }
    });
  }

  void _toggleGroup(_ExportGroup group, bool? value) {
    setState(() {
      final ids = group.chapters.map((c) => c.id.value);
      if (value == true) {
        _selected.addAll(ids);
      } else {
        _selected.removeAll(ids);
      }
    });
  }

  void _toggleChapter(ContentNode chapter) {
    setState(() {
      if (!_selected.remove(chapter.id.value)) {
        _selected.add(chapter.id.value);
      }
    });
  }

  void _toggleCollapse(String key) {
    setState(() {
      if (!_collapsed.remove(key)) {
        _collapsed.add(key);
      }
    });
  }

  bool _groupAllSelected(_ExportGroup group) =>
      group.chapters.isNotEmpty &&
      group.chapters.every((c) => _selected.contains(c.id.value));

  /// 当前选中章节的合计字数（characterCount 为空时按 0 计）。
  int get _selectedWordCount {
    var total = 0;
    for (final group in _groups) {
      for (final chapter in group.chapters) {
        if (_selected.contains(chapter.id.value)) {
          total += chapter.characterCount ?? 0;
        }
      }
    }
    return total;
  }

  /// 纯本地千分位格式化，避免为面板单独引入 intl 依赖。
  String _formatCount(int value) {
    assert(value >= 0, '_formatCount 仅处理非负字数');
    if (value == 0) {
      return '0';
    }
    final digits = value.toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        out.write(',');
      }
      out.write(digits[i]);
    }
    return out.toString();
  }

  Future<void> _export() async {
    if (_selected.isEmpty || _exporting) {
      return;
    }
    setState(() => _exporting = true);
    try {
      final name = _fileNameController.text.trim();
      final fileName = name.isEmpty ? '导出小说.txt' : name;

      // 先组正文：移动端 saveFile 返回系统托管的 URI（content:// 等），
      // dart:io 写不进去，只能用 bytes: 让插件内部写入；而 bytes 必须在调
      // saveFile 之前备好——故统一先组正文再弹框（桌面也走同一路径，跨平台一致）。
      final composed = await _composeSelectedChapters();
      if (composed == null) {
        return; // 无可导出内容，提示已在 _composeSelectedChapters 内给出。
      }

      final String? path;
      try {
        path = await FilePicker.saveFile(
          dialogTitle: '导出 TXT',
          fileName: fileName,
          bytes: utf8.encode(composed.text),
        );
      } on PlatformException {
        // file_picker 缺 entitlement / 底层异常时抛此；作用域仅限 saveFile。
        if (mounted) {
          showLibraryFailure(
            context,
            const LibraryFailure(
              code: LibraryFailureCode.io,
              message: '无法打开保存对话框。',
            ),
          );
        }
        return;
      }
      if (path == null || path.isEmpty) {
        return; // 用户取消
      }
      if (!mounted) {
        return;
      }
      // 先取 messenger 再 pop，避免 pop 后 context 失效。
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).maybePop();
      messenger.showSnackBar(
        SnackBar(
          content: Text('已导出 ${composed.chapterCount} 章到「$path」。'),
          duration: const Duration(seconds: 4),
        ),
      );
      // 导出成功后在宿主平台定位产出文件（macOS 走 `open -R`）；
      // 失败非致命（导出本身已成功）。实现经 widget.revealInFinder 注入，
      // 单测传 no-op 即可避免真的派生 Finder 进程。
      await widget.revealInFinder(path);
    } on LibraryOperationException catch (error) {
      if (mounted) {
        showLibraryFailure(context, error.failure);
      }
    } on Exception catch (error) {
      if (mounted) {
        showLibraryFailure(
          context,
          LibraryFailure(code: LibraryFailureCode.io, message: '导出失败：$error'),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  /// 按文档顺序读取选中章节并组装为导出正文。
  ///
  /// 返回 null 表示无可导出内容（已在内部提示）；否则返回正文文本与章节数。
  Future<({String text, int chapterCount})?> _composeSelectedChapters() async {
    final orderedChapters = <ContentNode>[];
    for (final group in _groups) {
      for (final chapter in group.chapters) {
        if (_selected.contains(chapter.id.value)) {
          orderedChapters.add(chapter);
        }
      }
    }
    final exportChapters = <ExportChapter>[];
    for (final chapter in orderedChapters) {
      final text = await widget.controller.readChapterRawText(
        widget.snapshot,
        chapter,
      );
      final breakIndex = text.indexOf('\n');
      final title = breakIndex < 0 ? text : text.substring(0, breakIndex);
      final body = breakIndex < 0 ? '' : text.substring(breakIndex + 1);
      exportChapters.add(ExportChapter(title: title, body: body));
    }
    final composed = TxtExportComposer.compose(
      chapters: exportChapters,
      options: TxtExportOptions(
        includeTitles: _includeTitles,
        blankLineBetween: _blankLineBetween,
      ),
    );
    if (composed.isEmpty) {
      if (mounted) {
        showLibraryFailure(
          context,
          const LibraryFailure(
            code: LibraryFailureCode.unsupportedFormat,
            message: '所选章节均为空，没有可导出的内容。',
          ),
        );
      }
      return null;
    }
    return (text: composed, chapterCount: exportChapters.length);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final title = widget.snapshot.metadata.title;
    return Dialog(
      backgroundColor: colorScheme.surfaceContainerHigh,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.file_download_outlined,
                    size: 22,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '导出 · $title',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '约 ${_formatCount(_selectedWordCount)} 字 · TXT 合并文件',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Divider(height: 1, color: colorScheme.outlineVariant),
              const SizedBox(height: 8),
              // 选项行。
              Row(
                children: [
                  Expanded(
                    child: _OptionChip(
                      label: '包含章节标题',
                      value: _includeTitles,
                      onChanged: (v) => setState(() => _includeTitles = v),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _OptionChip(
                      label: '章节间空行',
                      value: _blankLineBetween,
                      onChanged: (v) => setState(() => _blankLineBetween = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 全选行。
              InkWell(
                onTap: () => _toggleAll(!_allSelected),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _allSelected,
                        onChanged: _toggleAll,
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '全选（${_selected.length}/${_allIds.length}）',
                        style: textTheme.labelLarge,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    for (final group in _groups) ...[
                      _groupHeader(group),
                      if (!_collapsed.contains(group.key))
                        for (final chapter in group.chapters)
                          _chapterRow(chapter),
                      const SizedBox(height: 6),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _fileNameController,
                decoration: const InputDecoration(
                  labelText: '文件名',
                  helperText: '保存位置将在下一步选择。',
                  isDense: true,
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description_outlined, size: 18),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _exporting
                        ? null
                        : () => Navigator.of(context).maybePop(),
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.onSurfaceVariant,
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: (_selected.isEmpty || _exporting)
                        ? null
                        : _export,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: _exporting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_outlined, size: 18),
                    label: const Text('导出'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _groupHeader(_ExportGroup group) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final collapsed = _collapsed.contains(group.key);
    // 仅在多分组时提供展开/收起：卷右键场景只有一个分组，收起会把面板清空。
    final canCollapse = _groups.length > 1;

    Widget label = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          if (canCollapse) ...[
            Icon(
              collapsed ? Icons.chevron_right : Icons.expand_more,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 2),
          ],
          Icon(Icons.folder_outlined, size: 16, color: colorScheme.secondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              group.label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          Text(
            '${group.chapters.length} 章',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
    // 点击卷名区域只切换展开/收起，便于浏览长卷目录。
    if (canCollapse) {
      label = InkWell(
        onTap: () => _toggleCollapse(group.key),
        borderRadius: BorderRadius.circular(8),
        child: label,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          // 复选框单独负责「整卷选择/取消」，不与展开收起的点击区重叠。
          Checkbox(
            value: _groupAllSelected(group),
            onChanged: (v) => _toggleGroup(group, v),
            visualDensity: VisualDensity.compact,
          ),
          Expanded(child: label),
        ],
      ),
    );
  }

  Widget _chapterRow(ContentNode chapter) {
    return InkWell(
      onTap: () => _toggleChapter(chapter),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.only(left: 24, right: 4),
        child: Row(
          children: [
            Checkbox(
              value: _selected.contains(chapter.id.value),
              onChanged: (_) => _toggleChapter(chapter),
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: Text(
                _chapterLabel(chapter),
                style: const TextStyle(fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: value
              ? colorScheme.primaryContainer.withValues(alpha: 0.55)
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: value
                ? colorScheme.primary.withValues(alpha: 0.4)
                : colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 16,
              color: value ? colorScheme.primary : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}

String _chapterLabel(ContentNode node) {
  if (node.number != null) {
    return '第${node.number}章';
  }
  return _lastSegment(node.relativePath);
}

String _volumeLabel(ContentNode node) {
  if (node.number != null) {
    return '第${node.number}卷';
  }
  return _lastSegment(node.relativePath);
}

String _lastSegment(String path) {
  final segments = path.split('/');
  var last = segments.isEmpty ? path : segments.last;
  final dot = last.lastIndexOf('.');
  if (dot > 0) {
    last = last.substring(0, dot);
  }
  return last;
}
