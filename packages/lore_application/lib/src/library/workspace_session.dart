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

final class WorkspaceSessionSnapshot {
  const WorkspaceSessionSnapshot({
    required this.documents,
    required this.activePath,
    this.expandedDirectoryPaths = const [],
  });

  final List<WorkspaceDocumentState> documents;
  final String? activePath;
  final List<String> expandedDirectoryPaths;
}
