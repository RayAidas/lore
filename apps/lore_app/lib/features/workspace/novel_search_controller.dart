import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_editor/lore_editor.dart';

import '../library/library_providers.dart';
import 'workspace_controller.dart';

/// 一条章节内的单个匹配。
final class ChapterMatch {
  const ChapterMatch({
    required this.bodyOffset,
    required this.length,
    required this.snippet,
    required this.snippetMatchStart,
    required this.snippetMatchEnd,
  });

  /// 匹配在正文（去标题行后）中的起点；可直接用于打开章节的编辑器文本。
  final int bodyOffset;
  final int length;

  /// 匹配附近的上下文片段（换行已转空格，便于单行展示）。
  final String snippet;

  /// 匹配在 [snippet] 内的区间 `[snippetMatchStart, snippetMatchEnd)`，供 UI 高亮。
  final int snippetMatchStart;
  final int snippetMatchEnd;
}

/// 一个章节的跨章节搜索结果。
final class ChapterSearchResult {
  const ChapterSearchResult({
    required this.chapterId,
    required this.title,
    required this.relativePath,
    required this.matches,
  });

  final ContentId chapterId;
  final String title;

  /// 完整文档相对路径（session 根基准），[WorkspaceController.openPath] 跳转用。
  final String relativePath;

  final List<ChapterMatch> matches;
}

/// 小说内跨章节搜索的可观察状态：异步、防抖、isolate 化、可取消（generation 守卫）。
/// 复用 [SearchQuery.findAllIn] 做匹配；已打开章节复用 [OpenDocument] 内存文本，
/// 未打开章节走 [LibraryWorkspaceService.readDocument] 读盘。
///
/// 跨章节只搜不替——替换仍由单文档查找替换（⌘H）承担。
final class NovelSearchController extends ChangeNotifier {
  NovelSearchController({required this.workspace, required this.session})
    : _scopeNovelId = _scopeIdFor(workspace),
      _scopeTreeRevision = workspace.treeRevision {
    workspace.addListener(_handleWorkspaceChanged);
  }

  final WorkspaceController workspace;
  final LibrarySession session;

  String _pattern = '';
  bool _caseSensitive = false;
  bool _useRegex = false;
  List<ChapterSearchResult> _results = const [];
  bool _searching = false;
  int _searchGeneration = 0;
  Timer? _debounce;
  bool _disposed = false;
  NovelId? _scopeNovelId;
  int _scopeTreeRevision;

  String get pattern => _pattern;
  bool get caseSensitive => _caseSensitive;
  bool get useRegex => _useRegex;
  List<ChapterSearchResult> get results => _results;
  bool get searching => _searching;
  int get totalMatches => _results.fold(0, (sum, r) => sum + r.matches.length);
  int get chapterHits => _results.length;

  /// 当前搜索范围：优先跟随当前正在编辑的文档所属小说，次选工作区选中小说。
  NovelSnapshot? get scopeNovel =>
      workspace.activeNovel ?? workspace.selectedNovel;

  static NovelId? _scopeIdFor(WorkspaceController workspace) {
    final novel = workspace.activeNovel ?? workspace.selectedNovel;
    return novel?.metadata.id;
  }

  void _handleWorkspaceChanged() {
    if (_disposed) return;
    final scopeId = _scopeIdFor(workspace);
    final treeRevision = workspace.treeRevision;
    if (scopeId == _scopeNovelId && treeRevision == _scopeTreeRevision) {
      return;
    }
    _scopeNovelId = scopeId;
    _scopeTreeRevision = treeRevision;
    _schedule();
    notifyListeners();
  }

  void setPattern(String value) {
    if (_disposed) return;
    _pattern = value;
    _schedule();
    notifyListeners();
  }

  void setCaseSensitive(bool value) {
    if (_disposed) return;
    _caseSensitive = value;
    _schedule();
    notifyListeners();
  }

  void setUseRegex(bool value) {
    if (_disposed) return;
    _useRegex = value;
    _schedule();
    notifyListeners();
  }

  /// 面板初始化时同步偏好默认值。
  void applyDefaults({required bool matchCase, required bool useRegex}) {
    if (_disposed) return;
    _caseSensitive = matchCase;
    _useRegex = useRegex;
    notifyListeners();
  }

  void _schedule() {
    // 使正在进行的旧搜索失效：清空 pattern、切大小写/正则都要让旧 runSearch 在
    // await 点判定 generation 不匹配而丢弃，否则旧结果会写回（搜索框清空后结果
    // 又冒出来）。
    _searchGeneration += 1;
    _debounce?.cancel();
    if (_pattern.isEmpty) {
      _results = const [];
      _searching = false;
      return;
    }
    _searching = true;
    _debounce = Timer(const Duration(milliseconds: 250), runSearch);
  }

  Future<void> runSearch() async {
    if (_disposed) return;
    final pattern = _pattern;
    final novel = scopeNovel;
    final generation = ++_searchGeneration;
    if (pattern.isEmpty || novel == null) {
      _results = const [];
      _searching = false;
      notifyListeners();
      return;
    }
    _searching = true;
    notifyListeners();

    final format = novel.metadata.chapterFormat == ChapterFormat.markdown
        ? DocumentFormat.markdown
        : DocumentFormat.text;
    final markdown = format == DocumentFormat.markdown;

    final chapters = novel.contentTree.nodes
        .where((n) => n.type == ContentNodeType.chapter)
        .toList();
    final openedByPath = {
      for (final d in workspace.documents) d.relativePath: d,
    };

    // 读正文：已打开章节复用内存文本，其余读盘。逐章 await 以便中途被取消。
    final bodies = <String>[];
    final meta = <_ChapterMeta>[];
    for (final node in chapters) {
      final fullPath = '${novel.rootPath}/${node.relativePath}';
      String body;
      String title;
      final opened = openedByPath[fullPath];
      if (opened != null) {
        // OpenDocument 的编辑器只持有正文，不能再次 bodyOf，否则会丢掉正文首行。
        body = opened.editorController.text;
        title = ChapterTitleText.titleLine(
          opened.chapterNumber ?? node.number ?? 0,
          opened.chapterTitleSubtitle,
        );
      } else {
        try {
          final doc = await workspace.service.readDocument(
            session,
            DocumentRef(relativePath: fullPath, format: format),
          );
          final fullText = doc.text;
          body = ChapterTitleText.bodyOf(fullText);
          final parts = ChapterTitleText.tryParse(fullText, markdown: markdown);
          title = parts != null
              ? ChapterTitleText.titleLine(parts.number, parts.subtitle)
              : ChapterTitleText.prefix(node.number ?? 0);
        } catch (_) {
          continue; // 读失败的章节跳过，不阻断整本搜索。
        }
      }
      if (generation != _searchGeneration) return; // 已被新搜索取代。
      bodies.add(body);
      meta.add(_ChapterMeta(node.id, title, fullPath));
    }

    // isolate 批量匹配（纯 CPU，避免大章节卡 UI）。
    final query = SearchQuery(
      pattern: pattern,
      caseSensitive: _caseSensitive,
      useRegex: _useRegex,
    );
    final raw = await Isolate.run(() => matchChapters(bodies, query));
    if (_disposed || generation != _searchGeneration) return;

    final results = <ChapterSearchResult>[];
    for (var i = 0; i < meta.length; i++) {
      final matches = raw[i];
      if (matches.isEmpty) continue;
      results.add(
        ChapterSearchResult(
          chapterId: meta[i].chapterId,
          title: meta[i].title,
          relativePath: meta[i].relativePath,
          matches: matches,
        ),
      );
    }
    _results = results;
    _searching = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    workspace.removeListener(_handleWorkspaceChanged);
    super.dispose();
  }
}

/// 对每章正文跑 query 并构造带上下文的匹配列表。纯函数、isolate 安全
/// （不捕获 this），公开以供单测覆盖匹配与片段逻辑。
List<List<ChapterMatch>> matchChapters(List<String> bodies, SearchQuery query) {
  const radius = 20;
  return bodies.map((body) {
    return query.findAllIn(body).map((m) {
      final from = (m.start - radius).clamp(0, body.length);
      final to = (m.end + radius).clamp(0, body.length);
      final left = from > 0 ? '…' : '';
      final right = to < body.length ? '…' : '';
      // 换行转空格（单字符替换单字符，offset 不变）便于单行展示。
      final core = body.substring(from, to).replaceAll('\n', ' ');
      return ChapterMatch(
        bodyOffset: m.start,
        length: m.length,
        snippet: '$left$core$right',
        snippetMatchStart: left.length + (m.start - from),
        snippetMatchEnd: left.length + (m.end - from),
      );
    }).toList();
  }).toList();
}

class _ChapterMeta {
  const _ChapterMeta(this.chapterId, this.title, this.relativePath);

  final ContentId chapterId;
  final String title;
  final String relativePath;
}

/// 跨章节搜索状态（按 session family，随工作区生命周期）。
final novelSearchControllerProvider = Provider.autoDispose
    .family<NovelSearchController, LibrarySession>((ref, session) {
      final controller = NovelSearchController(
        workspace: ref.watch(workspaceControllerProvider(session)),
        session: session,
      );
      ref.onDispose(controller.dispose);
      return controller;
    });
