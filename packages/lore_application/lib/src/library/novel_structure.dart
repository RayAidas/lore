import 'package:lore_domain/lore_domain.dart';

import 'deletion.dart';
import 'library_bootstrap.dart';
import 'library_mutation_coordinator.dart';
import '../ports/content_tree_repository.dart';
import '../ports/novel_repository.dart';

final class NovelSnapshot {
  const NovelSnapshot({
    required this.rootPath,
    required this.metadata,
    required this.contentTree,
  });

  final String rootPath;
  final NovelMetadata metadata;
  final ContentTree contentTree;
}

final class PathChange {
  const PathChange({required this.oldPath, required this.newPath});

  final String oldPath;
  final String newPath;
}

final class NovelStructureMutation {
  const NovelStructureMutation({
    required this.snapshot,
    this.entry,
    this.pathChanges = const [],
  });

  final NovelSnapshot snapshot;

  /// 结构操作（建卷/章、重命名、移动）选中并暴露的目标条目；字数更新等不
  /// 改变选中的操作传 `null`，[_applyStructureMutation] 据此跳过选中。
  final LibraryEntry? entry;

  final List<PathChange> pathChanges;
}

final class ReconciliationIssue {
  const ReconciliationIssue({required this.message, this.relativePath});

  final String message;
  final String? relativePath;
}

final class NovelReconciliationResult {
  const NovelReconciliationResult({
    required this.snapshot,
    this.issues = const [],
  });

  final NovelSnapshot snapshot;
  final List<ReconciliationIssue> issues;
}

final class NovelStructureService {
  const NovelStructureService({
    required this.novelRepository,
    required this.contentTreeRepository,
    this.mutationCoordinator,
  });

  final NovelRepository novelRepository;
  final ContentTreeRepository contentTreeRepository;
  final LibraryMutationCoordinator? mutationCoordinator;

  Future<List<NovelSnapshot>> listNovels(LibrarySession session) {
    return novelRepository.listNovels(session.access);
  }

  Future<NovelSnapshot> loadNovel(
    LibrarySession session, {
    required NovelId novelId,
  }) {
    return novelRepository.loadNovel(session.access, novelId: novelId);
  }

  Future<NovelStructureMutation> createNovel(
    LibrarySession session, {
    required String title,
    ChapterFormat chapterFormat = ChapterFormat.markdown,
  }) {
    return _mutate(
      session,
      () => novelRepository.createNovel(
        session.access,
        title: title,
        chapterFormat: chapterFormat,
      ),
    );
  }

  /// 由已解析的卷/章区段导入整本小说（TXT 导入入口）。经 [_mutate] 串行化，
  /// 避免与其它结构写操作并发覆盖 content.json。
  Future<NovelStructureMutation> importNovel(
    LibrarySession session, {
    required String title,
    required List<ParsedSection> sections,
    ChapterFormat chapterFormat = ChapterFormat.text,
  }) {
    return _mutate(
      session,
      () => novelRepository.importNovel(
        session.access,
        title: title,
        sections: sections,
        chapterFormat: chapterFormat,
      ),
    );
  }

  Future<NovelStructureMutation> registerExistingNovel(
    LibrarySession session, {
    required String relativePath,
  }) {
    return _mutate(
      session,
      () => novelRepository.registerExistingNovel(
        session.access,
        relativePath: relativePath,
      ),
    );
  }

  Future<NovelStructureMutation> createVolume(
    LibrarySession session, {
    required NovelId novelId,
  }) {
    return _mutate(
      session,
      () =>
          contentTreeRepository.createVolume(session.access, novelId: novelId),
    );
  }

  Future<NovelStructureMutation> renameNovel(
    LibrarySession session, {
    required NovelId novelId,
    required String newName,
  }) {
    return _mutate(
      session,
      () => novelRepository.renameNovel(
        session.access,
        novelId: novelId,
        newName: newName,
      ),
    );
  }

  Future<NovelStructureMutation> renameBody(
    LibrarySession session, {
    required NovelId novelId,
    required String newName,
  }) {
    return _mutate(
      session,
      () => novelRepository.renameBody(
        session.access,
        novelId: novelId,
        newName: newName,
      ),
    );
  }

  Future<NovelStructureMutation> createChapter(
    LibrarySession session, {
    required NovelId novelId,
    ContentId? volumeId,
  }) {
    return _mutate(
      session,
      () => contentTreeRepository.createChapter(
        session.access,
        novelId: novelId,
        volumeId: volumeId,
      ),
    );
  }

  Future<NovelStructureMutation> updateChapterCharacterCounts(
    LibrarySession session, {
    required NovelId novelId,
    required Map<ContentId, int> characterCounts,
  }) {
    return _mutate(
      session,
      () => contentTreeRepository.updateChapterCharacterCounts(
        session.access,
        novelId: novelId,
        characterCounts: characterCounts,
      ),
    );
  }

  Future<NovelStructureMutation> renameNode(
    LibrarySession session, {
    required NovelId novelId,
    required ContentId nodeId,
    required String newName,
  }) {
    return _mutate(
      session,
      () => contentTreeRepository.renameNode(
        session.access,
        novelId: novelId,
        nodeId: nodeId,
        newName: newName,
      ),
    );
  }

  Future<NovelStructureMutation> moveChapter(
    LibrarySession session, {
    required NovelId novelId,
    required ContentId chapterId,
    ContentId? volumeId,
  }) {
    return _mutate(
      session,
      () => contentTreeRepository.moveChapter(
        session.access,
        novelId: novelId,
        chapterId: chapterId,
        volumeId: volumeId,
      ),
    );
  }

  Future<NovelStructureMutation> reorderNode(
    LibrarySession session, {
    required NovelId novelId,
    required ContentId nodeId,
    required int newIndex,
  }) {
    return _mutate(
      session,
      () => contentTreeRepository.reorderNode(
        session.access,
        novelId: novelId,
        nodeId: nodeId,
        newIndex: newIndex,
      ),
    );
  }

  Future<DeletionResult> deleteNode(
    LibrarySession session, {
    required NovelId novelId,
    required ContentId nodeId,
  }) {
    return _mutate(
      session,
      () => contentTreeRepository.deleteNode(
        session.access,
        novelId: novelId,
        nodeId: nodeId,
      ),
    );
  }

  Future<DeletionResult> deleteNovel(
    LibrarySession session, {
    required NovelId novelId,
  }) {
    return _mutate(
      session,
      () => novelRepository.deleteNovel(session.access, novelId: novelId),
    );
  }

  Future<NovelReconciliationResult> reconcile(
    LibrarySession session, {
    required NovelId novelId,
  }) {
    return _mutate(
      session,
      () => contentTreeRepository.reconcile(session.access, novelId: novelId),
    );
  }

  Future<T> _mutate<T>(LibrarySession session, Future<T> Function() operation) {
    final coordinator = mutationCoordinator;
    return coordinator == null
        ? operation()
        : coordinator.run(session.metadata.id, operation);
  }
}
