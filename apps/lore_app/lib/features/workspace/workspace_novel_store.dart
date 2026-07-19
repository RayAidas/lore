import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:path/path.dart' as p;

/// 工作区小说结构的内存快照存储：持有 novels 与 reconciliation issues，
/// 封装对 [NovelStructureService] 的调用与 issues 清理。
///
/// 不持有定时器、不做 UI notify——这些由 [WorkspaceController] 编排。
final class WorkspaceNovelStore {
  WorkspaceNovelStore({this.service, required this.session});

  final NovelStructureService? service;
  final LibrarySession session;
  final List<NovelSnapshot> _novels = [];
  final List<ReconciliationIssue> _issues = [];

  List<NovelSnapshot> get novels => List.unmodifiable(_novels);

  List<ReconciliationIssue> get issues => List.unmodifiable(_issues);

  NovelSnapshot? novelById(NovelId id) =>
      _novels.where((novel) => novel.metadata.id == id).firstOrNull;

  NovelSnapshot? novelByEntryValue(String? novelIdValue) {
    if (novelIdValue == null) {
      return null;
    }
    return _novels
        .where((novel) => novel.metadata.id.value == novelIdValue)
        .firstOrNull;
  }

  NovelId? novelIdForPath(String relativePath) {
    for (final novel in _novels) {
      if (relativePath == novel.rootPath ||
          p.isWithin(novel.rootPath, relativePath)) {
        return novel.metadata.id;
      }
    }
    return null;
  }

  /// 按文档相对路径查注册的章节节点：返回所属小说快照与节点。仅匹配
  /// [ContentNodeType.chapter]；散文件、卷目录、未注册文件返回 null。
  /// 用于副标题→文件名联动：只有注册章节才会触发重命名。
  ({NovelSnapshot novel, ContentNode node})? chapterNodeForPath(
    String relativePath,
  ) {
    for (final novel in _novels) {
      if (relativePath != novel.rootPath &&
          !p.isWithin(novel.rootPath, relativePath)) {
        continue;
      }
      final nodeRelative = relativePath == novel.rootPath
          ? ''
          : p.relative(relativePath, from: novel.rootPath);
      ContentNode? node;
      for (final candidate in novel.contentTree.nodes) {
        if (candidate.type == ContentNodeType.chapter &&
            candidate.relativePath == nodeRelative) {
          node = candidate;
          break;
        }
      }
      if (node != null) {
        return (novel: novel, node: node);
      }
    }
    return null;
  }

  void replace(NovelSnapshot snapshot) {
    final index = _novels.indexWhere(
      (novel) => novel.metadata.id == snapshot.metadata.id,
    );
    if (index < 0) {
      _novels.add(snapshot);
    } else {
      _novels[index] = snapshot;
    }
  }

  void remove(NovelId id) {
    _novels.removeWhere((novel) => novel.metadata.id == id);
  }

  /// 重新加载全部小说快照。成功返回 null，失败返回 [LibraryFailure]。
  Future<LibraryFailure?> load() async {
    final structureService = service;
    if (structureService == null) {
      return null;
    }
    try {
      final loaded = await structureService.listNovels(session);
      _novels
        ..clear()
        ..addAll(loaded);
      return null;
    } on LibraryOperationException catch (error) {
      return error.failure;
    }
  }

  /// reconcile 单本小说：刷新快照 + 按 novel 根清理旧 issues + 合并新 issues。
  /// 成功返回 null，失败返回 [LibraryFailure]。
  Future<LibraryFailure?> reconcile(NovelId novelId) async {
    final structureService = service;
    if (structureService == null) {
      return null;
    }
    try {
      final result = await structureService.reconcile(
        session,
        novelId: novelId,
      );
      replace(result.snapshot);
      _issues.removeWhere(
        (issue) =>
            issue.relativePath == null ||
            _novels.any(
              (novel) =>
                  novel.metadata.id == novelId &&
                  (issue.relativePath == novel.rootPath ||
                      p.isWithin(novel.rootPath, issue.relativePath!)),
            ),
      );
      _issues.addAll(result.issues);
      return null;
    } on LibraryOperationException catch (error) {
      return error.failure;
    }
  }
}
