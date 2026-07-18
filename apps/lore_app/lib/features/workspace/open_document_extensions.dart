import 'package:flutter/material.dart';

import 'workspace_controller.dart';

/// [OpenDocument] 保存状态的文案、图标、配色，供文档面板与信息面板复用。
extension SaveStatusIcons on OpenDocument {
  String get saveStatusText => switch (saveStatus) {
    DocumentSaveStatus.clean => '已保存',
    DocumentSaveStatus.dirty => '未保存',
    DocumentSaveStatus.saving => '保存中…',
    DocumentSaveStatus.conflict => '存在冲突',
    DocumentSaveStatus.error => '保存失败',
  };

  IconData get saveStatusIcon => switch (saveStatus) {
    DocumentSaveStatus.clean => Icons.check_circle_outline,
    DocumentSaveStatus.dirty => Icons.circle_outlined,
    DocumentSaveStatus.saving => Icons.sync,
    DocumentSaveStatus.conflict => Icons.warning_amber_rounded,
    DocumentSaveStatus.error => Icons.error_outline,
  };

  Color saveStatusColor(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return switch (saveStatus) {
      DocumentSaveStatus.clean => colorScheme.onSurfaceVariant,
      DocumentSaveStatus.dirty ||
      DocumentSaveStatus.saving => colorScheme.primary,
      DocumentSaveStatus.conflict => colorScheme.tertiary,
      DocumentSaveStatus.error => colorScheme.error,
    };
  }
}
