import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'workspace_controller.dart';

/// 文档标签条：水平滚动，展示已打开文档，支持激活与关闭。
final class DocumentTabs extends StatelessWidget {
  const DocumentTabs({
    required this.controller,
    required this.onClose,
    super.key,
  });

  final WorkspaceController controller;
  final Future<void> Function(WorkspaceTab tab) onClose;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (controller.tabs.isEmpty) {
      return ColoredBox(
        color: colorScheme.surfaceContainerLowest,
        child: const SizedBox(height: 46),
      );
    }
    return ColoredBox(
      color: colorScheme.surfaceContainerLowest,
      child: SizedBox(
        height: 46,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: controller.tabs.length,
          itemBuilder: (context, index) {
            final tab = controller.tabs[index];
            return ListenableBuilder(
              listenable: tab,
              builder: (context, _) {
                final active = controller.activePath == tab.relativePath;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Material(
                    color: active ? colorScheme.surface : Colors.transparent,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(8),
                    ),
                    child: InkWell(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(8),
                      ),
                      onTap: () => unawaited(controller.activateTab(tab)),
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 132,
                          maxWidth: 230,
                        ),
                        padding: const EdgeInsets.only(left: 14),
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(8),
                          ),
                          border: Border(
                            top: BorderSide(
                              color: active
                                  ? colorScheme.primary
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              p.extension(tab.name).toLowerCase() == '.md'
                                  ? Icons.description_outlined
                                  : Icons.text_snippet_outlined,
                              size: 16,
                              color: active
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                tab.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      fontWeight: active
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                    ),
                              ),
                            ),
                            if (tab.hasUnsavedChanges)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                child: Icon(
                                  Icons.circle,
                                  size: 7,
                                  color: colorScheme.primary,
                                ),
                              ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: '关闭',
                              onPressed: () => unawaited(onClose(tab)),
                              icon: const Icon(Icons.close, size: 15),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
