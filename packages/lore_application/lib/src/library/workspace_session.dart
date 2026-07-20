final class WorkspaceDocumentState {
  const WorkspaceDocumentState({
    required this.relativePath,
    required this.selectionBase,
    required this.selectionExtent,
    required this.scrollOffset,
  });

  final String relativePath;
  final int selectionBase;
  final int selectionExtent;
  final double scrollOffset;
}

/// 编辑器组标识。当前工作区最多支持左右两个组。
enum WorkspaceEditorGroupId { primary, secondary }

/// 单个编辑器组的标签顺序和活动标签。
final class WorkspaceEditorGroupState {
  const WorkspaceEditorGroupState({
    required this.id,
    required this.tabPaths,
    required this.activePath,
  });

  final WorkspaceEditorGroupId id;
  final List<String> tabPaths;
  final String? activePath;
}

final class WorkspaceSessionSnapshot {
  const WorkspaceSessionSnapshot({
    required this.documents,
    required this.activePath,
    this.expandedDirectoryPaths = const [],
    this.editorGroups = const [],
    this.focusedGroupId = WorkspaceEditorGroupId.primary,
    this.splitRatio = 0.5,
  });

  final List<WorkspaceDocumentState> documents;
  final String? activePath;
  final List<String> expandedDirectoryPaths;

  /// 空列表表示旧版单标签组会话；调用方应把 [documents] 映射到主组。
  final List<WorkspaceEditorGroupState> editorGroups;
  final WorkspaceEditorGroupId focusedGroupId;
  final double splitRatio;
}
