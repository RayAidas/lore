import 'package:lore_domain/lore_domain.dart';

import 'deletion.dart';
import 'library_bootstrap.dart';
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
    required this.entry,
    this.pathChanges = const [],
  });

  final NovelSnapshot snapshot;
  final LibraryEntry entry;
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
  });

  final NovelRepository novelRepository;
  final ContentTreeRepository contentTreeRepository;

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
    return novelRepository.createNovel(
      session.access,
      title: title,
      chapterFormat: chapterFormat,
    );
  }

  Future<NovelStructureMutation> registerExistingNovel(
    LibrarySession session, {
    required String relativePath,
  }) {
    return novelRepository.registerExistingNovel(
      session.access,
      relativePath: relativePath,
    );
  }

  Future<NovelStructureMutation> createVolume(
    LibrarySession session, {
    required NovelId novelId,
  }) {
    return contentTreeRepository.createVolume(session.access, novelId: novelId);
  }

  Future<NovelStructureMutation> renameNovel(
    LibrarySession session, {
    required NovelId novelId,
    required String newName,
  }) {
    return novelRepository.renameNovel(
      session.access,
      novelId: novelId,
      newName: newName,
    );
  }

  Future<NovelStructureMutation> renameBody(
    LibrarySession session, {
    required NovelId novelId,
    required String newName,
  }) {
    return novelRepository.renameBody(
      session.access,
      novelId: novelId,
      newName: newName,
    );
  }

  Future<NovelStructureMutation> createChapter(
    LibrarySession session, {
    required NovelId novelId,
    ContentId? volumeId,
  }) {
    return contentTreeRepository.createChapter(
      session.access,
      novelId: novelId,
      volumeId: volumeId,
    );
  }

  Future<NovelStructureMutation> renameNode(
    LibrarySession session, {
    required NovelId novelId,
    required ContentId nodeId,
    required String newName,
  }) {
    return contentTreeRepository.renameNode(
      session.access,
      novelId: novelId,
      nodeId: nodeId,
      newName: newName,
    );
  }

  Future<NovelStructureMutation> moveChapter(
    LibrarySession session, {
    required NovelId novelId,
    required ContentId chapterId,
    ContentId? volumeId,
  }) {
    return contentTreeRepository.moveChapter(
      session.access,
      novelId: novelId,
      chapterId: chapterId,
      volumeId: volumeId,
    );
  }

  Future<NovelStructureMutation> reorderNode(
    LibrarySession session, {
    required NovelId novelId,
    required ContentId nodeId,
    required int newIndex,
  }) {
    return contentTreeRepository.reorderNode(
      session.access,
      novelId: novelId,
      nodeId: nodeId,
      newIndex: newIndex,
    );
  }

  Future<DeletionResult> deleteNode(
    LibrarySession session, {
    required NovelId novelId,
    required ContentId nodeId,
  }) {
    return contentTreeRepository.deleteNode(
      session.access,
      novelId: novelId,
      nodeId: nodeId,
    );
  }

  Future<DeletionResult> deleteNovel(
    LibrarySession session, {
    required NovelId novelId,
  }) {
    return novelRepository.deleteNovel(session.access, novelId: novelId);
  }

  Future<NovelReconciliationResult> reconcile(
    LibrarySession session, {
    required NovelId novelId,
  }) {
    return contentTreeRepository.reconcile(session.access, novelId: novelId);
  }
}
