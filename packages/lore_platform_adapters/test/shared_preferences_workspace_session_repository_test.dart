import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_platform_adapters/lore_platform_adapters.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const libraryId = LibraryId('11111111-1111-4111-8111-111111111111');
  const key = 'lore.workspace.session.11111111-1111-4111-8111-111111111111';
  const repository = SharedPreferencesWorkspaceSessionRepository();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('round-trips expanded directory paths', () async {
    await repository.save(
      libraryId,
      const WorkspaceSessionSnapshot(
        documents: [],
        activePath: null,
        expandedDirectoryPaths: ['卷二', '卷一', '卷一'],
      ),
    );

    final restored = await repository.load(libraryId);

    expect(restored!.expandedDirectoryPaths, ['卷一', '卷二']);
  });

  test('loads version 1 sessions with no expanded directories', () async {
    SharedPreferences.setMockInitialValues({
      key: jsonEncode({
        'schemaVersion': 1,
        'activePath': null,
        'documents': <Object?>[],
      }),
    });

    final restored = await repository.load(libraryId);

    expect(restored, isNotNull);
    expect(restored!.expandedDirectoryPaths, isEmpty);
  });

  test('round-trips version 3 editor groups and split layout', () async {
    await repository.save(
      libraryId,
      const WorkspaceSessionSnapshot(
        documents: [
          WorkspaceDocumentState(
            relativePath: '左.txt',
            selectionBase: 1,
            selectionExtent: 1,
            scrollOffset: 12,
          ),
          WorkspaceDocumentState(
            relativePath: '右.md',
            selectionBase: 2,
            selectionExtent: 3,
            scrollOffset: 24,
          ),
        ],
        activePath: '右.md',
        editorGroups: [
          WorkspaceEditorGroupState(
            id: WorkspaceEditorGroupId.primary,
            tabPaths: ['左.txt'],
            activePath: '左.txt',
          ),
          WorkspaceEditorGroupState(
            id: WorkspaceEditorGroupId.secondary,
            tabPaths: ['右.md'],
            activePath: '右.md',
          ),
        ],
        focusedGroupId: WorkspaceEditorGroupId.secondary,
        splitRatio: 0.62,
      ),
    );

    final restored = await repository.load(libraryId);

    expect(restored!.editorGroups, hasLength(2));
    expect(restored.editorGroups.first.tabPaths, ['左.txt']);
    expect(restored.editorGroups.last.tabPaths, ['右.md']);
    expect(restored.focusedGroupId, WorkspaceEditorGroupId.secondary);
    expect(restored.splitRatio, 0.62);
  });
}
