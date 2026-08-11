import 'package:lore_domain/lore_domain.dart';

import '../library/library_bootstrap.dart';
import '../library/library_failure.dart';
import '../library/novel_structure.dart';
import '../ports/ai_chat_client.dart';
import '../ports/document_repository.dart';
import 'chapter_memory_doc.dart';
import 'memory_doc_entries.dart';

/// 每批最多送入模型的章节数（控制单次请求体积，避免长篇小说一次发送全文）。
const int _maxChaptersPerBatch = 15;

/// 单章正文最多送入模型的字符数；超出的部分截断并标注。
const int _maxChapterChars = 1200;

/// AI 章节记忆生成用例：把小说章节分批喂给模型，产出逐章摘要文档。
///
/// 记忆文档用于写作助手在对话中保持与历史章节一致。文档头（`# 章节记忆` +
/// `基于 N 章生成` 元数据行）由本服务固定生成、不经模型；条目标题统一重标为
/// 由章节元数据构造的规范标题（见 [canonicalHeadingFor]），模型输出只作匹配
/// 提示——编号漂移、模型改写、序章无编号都不影响文档结构。
///
/// [generateMemory] 整篇重建；[updateMemory] 支持增量（只摘要缺失章节）与
/// 指定章节更新，已有条目（含用户手改）原样保留。
final class MemoryGenerationService {
  const MemoryGenerationService({
    required this.client,
    required this.documentRepository,
  });

  final AiChatClient client;
  final DocumentRepository documentRepository;

  /// 生成章节记忆文档全文（含头部），可直接写入 `小说记忆.md`。
  ///
  /// [session] 提供书库访问，[novel] 提供根路径与章节树；每批使用比默认更长的
  /// 超时（180s，同大纲生成）。
  Future<String> generateMemory({
    required LibrarySession session,
    required NovelSnapshot novel,
    required WritingAgentConfig config,
    required String apiKey,
    Duration timeout = const Duration(seconds: 180),
  }) async {
    final chapters = await _readChapters(session, novel);
    if (chapters.isEmpty) {
      throw const AiRequestException('小说暂无已写章节，无法生成记忆');
    }

    final updates = <MemoryEntry>[];
    for (var start = 0; start < chapters.length; start += _maxChaptersPerBatch) {
      final end = (start + _maxChaptersPerBatch).clamp(0, chapters.length);
      final raw = await _complete(
        messages: _messagesForBatch(chapters.sublist(start, end)),
        config: config,
        apiKey: apiKey,
        timeout: timeout,
      );
      updates.addAll(_matchUpdates(chapters.sublist(start, end), raw));
    }

    return formatMemoryDoc(updates, chapterCount: _countCovered(updates, chapters));
  }

  /// 增量 / 指定章节更新记忆。
  ///
  /// [chapterIds] 为空或 null 时，只重新摘要**尚未在记忆文档中**的章节；非空时
  /// 只重新摘要指定章节（即使已有条目）。已有条目在合并中原样保留。
  ///
  /// 返回完整文档文本；若现有文档无法按锚点唯一寻址（perVolume 旧格式的裸
  /// `第N章` 条目、或任意锚点重复），自动回退整篇重建并置 [UpdateMemoryResult.rebuilt]。
  Future<UpdateMemoryResult> updateMemory({
    required LibrarySession session,
    required NovelSnapshot novel,
    required WritingAgentConfig config,
    required String apiKey,
    Set<ContentId>? chapterIds,
    Duration timeout = const Duration(seconds: 180),
  }) async {
    final chapters = await _readChapters(session, novel);
    if (chapters.isEmpty) {
      throw const AiRequestException('小说暂无已写章节，无法生成记忆');
    }

    final existingText = await _readExistingDoc(session, novel);
    final existing = parseMemoryEntries(existingText);

    // 迁移/歧义门：旧文档无法按锚点唯一寻址时整篇重建，避免追加出重复摘要。
    final needsRebuild = hasDuplicateKeys(existing) ||
        _needsMigration(
          existing,
          chapters,
          mode: novel.metadata.numberingMode,
        );
    if (needsRebuild) {
      final text = await generateMemory(
        session: session,
        novel: novel,
        config: config,
        apiKey: apiKey,
        timeout: timeout,
      );
      return UpdateMemoryResult(
        text: text,
        rebuilt: true,
        coveredChapterCount: _countCovered(parseMemoryEntries(text), chapters),
        updatedChapters: chapters.map((chapter) => chapter.id).toList(),
      );
    }

    final existingKeys = existing
        .map((entry) => entry.key)
        .whereType<MemoryKey>()
        .toSet();
    final targets = chapterIds != null && chapterIds.isNotEmpty
        ? chapterIds
              .where((id) => chapters.any((chapter) => chapter.id == id))
              .toSet()
        : chapters
              .where((chapter) => !existingKeys.contains(chapter.key))
              .map((chapter) => chapter.id)
              .toSet();

    if (targets.isEmpty) {
      return UpdateMemoryResult(
        text: existingText,
        rebuilt: false,
        coveredChapterCount: _countCovered(existing, chapters),
        updatedChapters: const [],
      );
    }

    final targetChapters = chapters
        .where((chapter) => targets.contains(chapter.id))
        .toList();
    final updates = <MemoryEntry>[];
    for (
      var start = 0;
      start < targetChapters.length;
      start += _maxChaptersPerBatch
    ) {
      final end = (start + _maxChaptersPerBatch).clamp(0, targetChapters.length);
      final batch = targetChapters.sublist(start, end);
      final raw = await _complete(
        messages: _messagesForBatch(batch),
        config: config,
        apiKey: apiKey,
        timeout: timeout,
      );
      updates.addAll(_matchUpdates(batch, raw));
    }

    final merged = mergeEntries(existing: existing, updates: updates);
    final covered = _countCovered(merged, chapters);
    return UpdateMemoryResult(
      text: formatMemoryDoc(merged, chapterCount: covered),
      rebuilt: false,
      coveredChapterCount: covered,
      updatedChapters: targetChapters.map((chapter) => chapter.id).toList(),
    );
  }

  /// 枚举章节树中所有章节节点（阅读序），逐个读取正文并截断。读失败或为空的
  /// 章节跳过，不让瞬时 IO 失败中断整体生成。
  Future<List<_Chapter>> _readChapters(
    LibrarySession session,
    NovelSnapshot novel,
  ) async {
    final tree = novel.contentTree;
    final mode = novel.metadata.numberingMode;
    final result = <_Chapter>[];
    for (
      final node
          in _chaptersInReadingOrder(tree, novel.metadata.body.id)
    ) {
      final isText = node.relativePath.toLowerCase().endsWith('.txt');
      final ref = DocumentRef(
        relativePath: _joinPath(novel.rootPath, node.relativePath),
        format: isText ? DocumentFormat.text : DocumentFormat.markdown,
      );
      final String text;
      try {
        final snapshot = await documentRepository.readDocument(
          session.access,
          ref,
        );
        text = snapshot.text;
      } on LibraryOperationException {
        continue;
      }
      final content = _toChapter(text, isText: isText);
      if (content.body.trim().isEmpty) {
        continue; // 只有标题行的章节视为空章。
      }
      result.add(
        _Chapter(
          id: node.id,
          node: node,
          canonicalHeading: canonicalHeadingFor(
            node: node,
            mode: mode,
            tree: tree,
            subtitle: content.subtitle,
          ),
          key: memoryKeyForNode(node: node, mode: mode, tree: tree),
          body: _truncate(content.body.trim(), _maxChapterChars),
        ),
      );
    }
    return result;
  }

  /// 读取现有记忆文档；不存在或读失败视为空（增量从零开始即全量）。
  Future<String> _readExistingDoc(
    LibrarySession session,
    NovelSnapshot novel,
  ) async {
    final ref = DocumentRef(
      relativePath: _joinPath(novel.rootPath, '$chapterMemoryDocName.md'),
      format: DocumentFormat.markdown,
    );
    try {
      final snapshot = await documentRepository.readDocument(
        session.access,
        ref,
      );
      return snapshot.text;
    } on LibraryOperationException {
      return '';
    }
  }

  /// 单批章节的请求消息：每章给出规范标题 + 截断后的正文。
  List<AiChatMessage> _messagesForBatch(List<_Chapter> batch) {
    final buffer = StringBuffer()..writeln('以下是本批需要总结的章节：');
    for (final chapter in batch) {
      buffer
        ..writeln()
        ..writeln('### ${chapter.canonicalHeading}')
        ..writeln(chapter.body);
    }
    return [
      const AiChatMessage(role: AiChatRole.system, content: _memorySystemPrompt),
      AiChatMessage(role: AiChatRole.user, content: buffer.toString().trim()),
    ];
  }

  /// 把模型输出解析成条目并匹配到目标章节。先按锚点匹配（对模型重排稳健，
  /// 且结果保持**目标顺序**，不随模型输出顺序漂移），剩余条目与未命中目标若
  /// 数量相等则按顺序兜底（覆盖模型省略卷前缀 / 编号错位）；数量不齐则抛错
  /// （本次不写盘，旧文档原样保留）。条目标题一律重标为目标的规范标题。
  List<MemoryEntry> _matchUpdates(List<_Chapter> targets, String rawOutput) {
    final sections = parseMemoryEntries(rawOutput);
    final used = List<bool>.filled(sections.length, false);
    final result = List<MemoryEntry?>.filled(targets.length, null);
    for (var t = 0; t < targets.length; t++) {
      final key = targets[t].key;
      for (var s = 0; s < sections.length; s++) {
        if (!used[s] && sections[s].key == key) {
          result[t] = _entryFor(targets[t], sections[s].body);
          used[s] = true;
          break;
        }
      }
    }
    final unmatchedSections = [
      for (var s = 0; s < sections.length; s++)
        if (!used[s]) sections[s],
    ];
    final unmatchedTargets = [
      for (var t = 0; t < targets.length; t++)
        if (result[t] == null) t,
    ];
    if (unmatchedSections.length != unmatchedTargets.length) {
      throw AiRequestException(
        '模型输出章节数量与本次目标不匹配（期望 ${targets.length} 个条目，'
        '实际得到 ${sections.length} 个），已取消本次更新',
      );
    }
    for (var i = 0; i < unmatchedTargets.length; i++) {
      final t = unmatchedTargets[i];
      result[t] = _entryFor(targets[t], unmatchedSections[i].body);
    }
    return result.whereType<MemoryEntry>().toList();
  }

  MemoryEntry _entryFor(_Chapter chapter, String body) {
    final text = body.trim();
    final raw = text.isEmpty
        ? '## ${chapter.canonicalHeading}'
        : '## ${chapter.canonicalHeading}\n\n$text';
    return MemoryEntry(
      heading: chapter.canonicalHeading,
      body: text,
      key: chapter.key,
      raw: raw,
    );
  }

  /// 合并后锚点命中当前章节的条目数（孤儿与不透明条目不计入），用作头部计数。
  int _countCovered(List<MemoryEntry> entries, List<_Chapter> chapters) {
    final chapterKeys = chapters.map((chapter) => chapter.key).toSet();
    return entries.where((entry) {
      final key = entry.key;
      return key != null && chapterKeys.contains(key);
    }).length;
  }

  /// perVolume 旧文档迁移判定：裸编号条目（无卷前缀）不属于任何正文根级章节时，
  /// 判定为 v1 旧格式（v2 起正文根级条目写作「未分卷 第N章」），需整篇重建一次。
  bool _needsMigration(
    List<MemoryEntry> existing,
    List<_Chapter> chapters, {
    required NumberingMode mode,
  }) {
    if (mode != NumberingMode.perVolume) {
      return false;
    }
    final bodyLevelKeys = chapters
        .map((chapter) => chapter.key)
        .whereType<MemoryKeyNumbered>()
        .where((key) => key.volume == null)
        .toSet();
    return existing.any((entry) {
      final key = entry.key;
      return key is MemoryKeyNumbered &&
          key.volume == null &&
          !bodyLevelKeys.contains(key);
    });
  }

  Future<String> _complete({
    required List<AiChatMessage> messages,
    required WritingAgentConfig config,
    required String apiKey,
    required Duration timeout,
  }) async {
    try {
      return await client.completeChat(
        baseUrl: config.baseUrl,
        apiKey: apiKey,
        model: config.model,
        messages: messages,
        timeout: timeout,
      );
    } on AiRequestException {
      rethrow;
    } catch (error) {
      // 客户端/解析等非预期失败统一包装成可展示的错误。
      throw AiRequestException('生成章节记忆失败：$error');
    }
  }
}

/// 增量 / 指定章节更新的结果。
final class UpdateMemoryResult {
  const UpdateMemoryResult({
    required this.text,
    required this.rebuilt,
    required this.coveredChapterCount,
    required this.updatedChapters,
  });

  /// 可直接写盘的完整文档文本。
  final String text;

  /// 是否因编号冲突或旧格式整篇重建（非增量）。
  final bool rebuilt;

  /// 合并后锚点命中当前章节的条目数。
  final int coveredChapterCount;

  /// 本次实际重新摘要的章节。
  final List<ContentId> updatedChapters;
}

/// 单章待总结内容：规范标题（重标锚点）、锚点与截断后的正文。
final class _Chapter {
  const _Chapter({
    required this.id,
    required this.node,
    required this.canonicalHeading,
    required this.key,
    required this.body,
  });

  final ContentId id;
  final ContentNode node;
  final String canonicalHeading;
  final MemoryKey key;
  final String body;
}

/// 由章节文件全文拆分标题副标题与正文；首行不是章节标题时整篇当正文。
({String subtitle, String body}) _toChapter(String text, {required bool isText}) {
  final parts = ChapterTitleText.tryParse(text, markdown: !isText);
  return (
    subtitle: parts?.subtitle ?? '',
    body: parts == null ? text : ChapterTitleText.bodyOf(text),
  );
}

String _truncate(String text, int max) {
  if (text.length <= max) {
    return text;
  }
  return '${text.substring(0, max)}\n……（正文过长，已截断）';
}

/// 全书章节阅读顺序：正文根级章节（parentId == body.id）在前，其后各卷按
/// `order` 升序、卷内章节按 [ContentTree.childrenOf]（已按 `order` 排序）串联。
/// [ContentTree.nodes] 的存储顺序不可靠，须显式排阅读序（同 app 层
/// `chapter_navigation.dart` 的约定）。
List<ContentNode> _chaptersInReadingOrder(ContentTree tree, ContentId bodyId) {
  final chapters = <ContentNode>[];
  for (final node in tree.childrenOf(bodyId)) {
    if (node.type == ContentNodeType.chapter) {
      chapters.add(node);
    }
  }
  final volumes = tree.nodes
      .where((node) => node.type == ContentNodeType.volume)
      .toList()
    ..sort((a, b) => a.order.compareTo(b.order));
  for (final volume in volumes) {
    for (final node in tree.childrenOf(volume.id)) {
      if (node.type == ContentNodeType.chapter) {
        chapters.add(node);
      }
    }
  }
  return chapters;
}

/// application 层不依赖 path 包：书库内相对路径统一使用 `/`，用字符串拼接。
String _joinPath(String root, String relative) {
  if (root.isEmpty) {
    return relative;
  }
  return root.endsWith('/') ? '$root$relative' : '$root/$relative';
}

/// 单批章节总结指令：逐章输出 `## 第X章` 条目，只陈述事实，不评价。
const _memorySystemPrompt = '''
你是一位资深的小说编辑。请阅读用户提供的若干章节正文，为每一章生成一段简洁的
中文摘要。

摘要需覆盖：本章核心情节、登场并互动的重要人物、关键设定与伏笔、以及本章结尾
的故事状态。

请严格按以下 Markdown 结构输出，只输出逐章条目，不要添加任何解释、前言或结尾：

## 第X章 章名
（2~3 行摘要，只陈述已发生的情节与状态，不做评价）

## 第Y章 章名
（下一章照此继续）
''';
