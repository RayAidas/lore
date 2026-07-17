import 'dart:convert';

import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class SharedPreferencesWorkspaceSessionRepository
    implements WorkspaceSessionRepository {
  const SharedPreferencesWorkspaceSessionRepository();

  static const _schemaVersion = 1;
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
      if (value is! Map<String, Object?> ||
          value['schemaVersion'] != _schemaVersion ||
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
      }),
    );
  }
}
