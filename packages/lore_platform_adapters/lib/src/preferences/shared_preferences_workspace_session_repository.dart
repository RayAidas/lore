import 'dart:convert';

import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local workspace session persistence.
final class SharedPreferencesWorkspaceSessionRepository
    implements WorkspaceSessionRepository {
  const SharedPreferencesWorkspaceSessionRepository();

  static const _schemaVersion = 3;
  static const _keyPrefix = 'lore.workspace.session.';

  @override
  Future<WorkspaceSessionSnapshot?> load(LibraryId libraryId) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString('$_keyPrefix${libraryId.value}');
    if (encoded == null) {
      return null;
    }
    try {
      final value = jsonDecode(encoded);
      final schemaVersion = value is Map<String, Object?>
          ? value['schemaVersion']
          : null;
      if (value is! Map<String, Object?> ||
          (schemaVersion != 1 &&
              schemaVersion != 2 &&
              schemaVersion != _schemaVersion) ||
          value['documents'] is! List<Object?>) {
        return null;
      }
      final documents = <WorkspaceDocumentState>[];
      for (final item in value['documents']! as List<Object?>) {
        if (item is! Map<String, Object?>) {
          continue;
        }
        final path = item['relativePath'];
        final selectionBase = item['selectionBase'];
        final selectionExtent = item['selectionExtent'];
        final scrollOffset = item['scrollOffset'];
        if (path is String &&
            selectionBase is int &&
            selectionExtent is int &&
            scrollOffset is num) {
          documents.add(
            WorkspaceDocumentState(
              relativePath: path,
              selectionBase: selectionBase,
              selectionExtent: selectionExtent,
              scrollOffset: scrollOffset.toDouble(),
            ),
          );
        }
      }
      return WorkspaceSessionSnapshot(
        documents: documents,
        activePath: value['activePath'] is String
            ? value['activePath']! as String
            : null,
        expandedDirectoryPaths: value['expandedDirectoryPaths'] is List<Object?>
            ? (value['expandedDirectoryPaths']! as List<Object?>)
                  .whereType<String>()
                  .toSet()
                  .toList()
            : const [],
        editorGroups: _readEditorGroups(value['editorGroups']),
        focusedGroupId:
            _readGroupId(value['focusedGroupId']) ??
            WorkspaceEditorGroupId.primary,
        splitRatio: _readSplitRatio(value['splitRatio']),
      );
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> save(
    LibraryId libraryId,
    WorkspaceSessionSnapshot snapshot,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      '$_keyPrefix${libraryId.value}',
      jsonEncode({
        'schemaVersion': _schemaVersion,
        'activePath': snapshot.activePath,
        'focusedGroupId': snapshot.focusedGroupId.name,
        'splitRatio': snapshot.splitRatio,
        'expandedDirectoryPaths':
            snapshot.expandedDirectoryPaths.toSet().toList()..sort(),
        'documents': snapshot.documents
            .map(
              (document) => {
                'relativePath': document.relativePath,
                'selectionBase': document.selectionBase,
                'selectionExtent': document.selectionExtent,
                'scrollOffset': document.scrollOffset,
              },
            )
            .toList(),
        'editorGroups': snapshot.editorGroups
            .map(
              (group) => {
                'id': group.id.name,
                'tabPaths': group.tabPaths,
                'activePath': group.activePath,
              },
            )
            .toList(),
      }),
    );
  }

  static List<WorkspaceEditorGroupState> _readEditorGroups(Object? value) {
    if (value is! List<Object?>) {
      return const [];
    }
    final groups = <WorkspaceEditorGroupState>[];
    final seenIds = <WorkspaceEditorGroupId>{};
    for (final item in value) {
      if (item is! Map<String, Object?>) {
        continue;
      }
      final id = _readGroupId(item['id']);
      final paths = item['tabPaths'];
      if (id == null || !seenIds.add(id) || paths is! List<Object?>) {
        continue;
      }
      groups.add(
        WorkspaceEditorGroupState(
          id: id,
          tabPaths: paths.whereType<String>().toList(),
          activePath: item['activePath'] is String
              ? item['activePath']! as String
              : null,
        ),
      );
    }
    return groups;
  }

  static WorkspaceEditorGroupId? _readGroupId(Object? value) {
    return switch (value) {
      'primary' => WorkspaceEditorGroupId.primary,
      'secondary' => WorkspaceEditorGroupId.secondary,
      _ => null,
    };
  }

  static double _readSplitRatio(Object? value) {
    if (value is! num || !value.isFinite) {
      return 0.5;
    }
    return value.toDouble().clamp(0.3, 0.7).toDouble();
  }
}
