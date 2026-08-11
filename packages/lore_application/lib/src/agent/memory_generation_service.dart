import 'package:lore_domain/lore_domain.dart';

import '../library/library_bootstrap.dart';
import '../library/library_failure.dart';
import '../library/novel_structure.dart';
import '../ports/ai_chat_client.dart';
import '../ports/document_repository.dart';
import 'chapter_memory_doc.dart';

/// 每批最多送入模型的章节数（控制单次请求体积，避免长篇小说一次发送全文）。
const int _maxChaptersPerBatch = 15;

/// 单章正文最多送入模型的字符数；超出的部分截断并标注。
const int _maxChapterChars = 1200;

/// AI 章节记忆生成用例：把小说全部已写章节分批喂给模型，产出逐章摘要文档。
///
/// 记忆文档用于写作助手在对话中保持与历史章节一致。文档头（`# 章节记忆` +
/// `基于 N 章生成` 元数据行）由本服务固定生成、不经模型，保证结构稳定；模型
/// 只负责输出逐章 `## 第X章` 条目。分批结果的逐章条目相互独立，直接拼接即可，
/// 无需额外合并调用。
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

    final sections = <String>[];
    for (var start = 0; start < chapters.length; start += _maxChaptersPerBatch) {
      final end = (start + _maxChaptersPerBatch).clamp(0, chapters.length);
      final section = await _complete(
        messages: _messagesForBatch(chapters.sublist(start, end)),
        config: config,
        apiKey: apiKey,
        timeout: timeout,
      );
      sections.add(section.trim());
    }

    return _wrapDocument(sections, chapterCount: chapters.length);
  }

  /// 枚举章节树中所有章节节点，逐个读取正文并截断。读失败或为空的章节跳过，
  /// 不让瞬时 IO 失败中断整体生成。
  Future<List<_ChapterText>> _readChapters(
    LibrarySession session,
    NovelSnapshot novel,
  ) async {
    final result = <_ChapterText>[];
    for (final node in novel.contentTree.nodes) {
      if (node.type != ContentNodeType.chapter) {
        continue;
      }
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
      final chapter = _toChapter(
        text,
        isText: isText,
        fallbackNumber: node.number,
      );
      if (chapter.body.isEmpty) {
        continue; // 只有标题行的章节视为空章。
      }
      result.add(chapter);
    }
    return result;
  }

  /// 单批章节的请求消息：每章给出标题行 + 截断后的正文。
  List<AiChatMessage> _messagesForBatch(List<_ChapterText> batch) {
    final buffer = StringBuffer()..writeln('以下是本批需要总结的章节：');
    for (final chapter in batch) {
      buffer
        ..writeln()
        ..writeln('### ${chapter.heading}')
        ..writeln(chapter.body);
    }
    return [
      const AiChatMessage(role: AiChatRole.system, content: _memorySystemPrompt),
      AiChatMessage(role: AiChatRole.user, content: buffer.toString().trim()),
    ];
  }

  String _wrapDocument(List<String> sections, {required int chapterCount}) {
    final buffer = StringBuffer()
      ..writeln(formatMemoryHeader(chapterCount))
      ..writeln()
      ..write(sections.join('\n\n'));
    return buffer.toString().trim();
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

/// 单章待总结内容：标题行（如 `第3章 甜蜜的家`）与截断后的正文。
final class _ChapterText {
  const _ChapterText({required this.heading, required this.body});

  final String heading;
  final String body;
}

/// 由章节文件全文拆分标题与正文；首行不是章节标题时（异常文件）回退用
/// [fallbackNumber] 编标题、整篇当正文。
_ChapterText _toChapter(
  String text, {
  required bool isText,
  required int? fallbackNumber,
}) {
  final parts = ChapterTitleText.tryParse(text, markdown: !isText);
  final number = parts?.number ?? fallbackNumber;
  final subtitle = parts?.subtitle ?? '';
  final heading = number == null
      ? '未编号章节'
      : subtitle.trim().isEmpty
          ? '第$number章'
          : '第$number章 $subtitle';
  final body = parts == null ? text : ChapterTitleText.bodyOf(text);
  return _ChapterText(
    heading: heading,
    body: _truncate(body.trim(), _maxChapterChars),
  );
}

String _truncate(String text, int max) {
  if (text.length <= max) {
    return text;
  }
  return '${text.substring(0, max)}\n……（正文过长，已截断）';
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
