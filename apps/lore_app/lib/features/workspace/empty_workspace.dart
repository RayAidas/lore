import 'package:flutter/material.dart';

/// 工作区内容区无文档打开时的占位状态。
final class EmptyWorkspace extends StatelessWidget {
  const EmptyWorkspace({
    required this.hasSelection,
    this.selectedPath,
    super.key,
  });

  final bool hasSelection;
  final String? selectedPath;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              hasSelection
                  ? Icons.folder_open_outlined
                  : Icons.edit_note_outlined,
              size: 30,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            hasSelection ? '已选择一个书库项目' : '开始你的写作',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            hasSelection ? selectedPath! : '从左侧选择文件，或新建一部小说',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (!hasSelection) ...[
            const SizedBox(height: 8),
            Text(
              '选择或新建文件开始写作',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
