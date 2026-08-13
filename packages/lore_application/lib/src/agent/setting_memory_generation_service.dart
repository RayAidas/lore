import 'package:lore_domain/lore_domain.dart';

import '../library/library_bootstrap.dart';
import '../library/library_failure.dart';
import '../library/novel_structure.dart';
import '../ports/ai_chat_client.dart';
import '../ports/document_repository.dart';
import 'chapter_memory_doc.dart';
import 'setting_memory_doc.dart';

/// 章节记忆全文单次送入模型的安全上限（字符）；超出的部分截断并标注。
const int _maxMemoryChars = 30000;

/// AI 设定记忆生成用例：读章节记忆文档，让模型二次提炼为结构化设定文档
/// （人物 / 地点 / 时间线 / 伏笔）。
///
/// 设定记忆是章节记忆的派生产物：v1 只做整篇重建（[generateSettingMemory]），
/// 由用户手动触发；增量合并与联动更新留待后续版本。文档头（`# 设定记忆` +
/// `基于章节记忆生成` 元数据行）由本服务固定生成、不经模型。
final class SettingMemoryGenerationService {
  const SettingMemoryGenerationService({
    required this.client,
    required this.documentRepository,
  });

  final AiChatClient client;
  final DocumentRepository documentRepository;

  /// 生成设定记忆文档全文（含头部），可直接写入 `设定记忆.md`。
  ///
  /// 读取小说根目录下的章节记忆文档作为提炼输入；不存在或空白时抛
  /// [AiRequestException]，提示先生成章节记忆。
  Future<String> generateSettingMemory({
    required LibrarySession session,
    required NovelSnapshot novel,
    required WritingAgentConfig config,
    required String apiKey,
    Duration timeout = const Duration(seconds: 180),
  }) async {
    final memoryText = await _readChapterMemory(session, novel);
    if (memoryText.trim().isEmpty) {
      throw const AiRequestException('请先生成章节记忆，再生成设定记忆');
    }

    final raw = await _complete(
      messages: [
        const AiChatMessage(
          role: AiChatRole.system,
          content: _settingMemorySystemPrompt,
        ),
        AiChatMessage(
          role: AiChatRole.user,
          content: '以下是章节记忆全文，请据此提炼结构化设定：\n'
              '${_truncate(memoryText, _maxMemoryChars)}',
        ),
      ],
      config: config,
      apiKey: apiKey,
      timeout: timeout,
    );
    return '${formatSettingMemoryHeader()}\n\n${raw.trim()}';
  }

  /// 读取章节记忆文档；不存在或读失败视为空（上层据此要求先生成章节记忆）。
  Future<String> _readChapterMemory(
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
      throw AiRequestException('生成设定记忆失败：$error');
    }
  }
}

/// application 层不依赖 path 包：书库内相对路径统一使用 `/`，用字符串拼接。
String _joinPath(String root, String relative) {
  if (root.isEmpty) {
    return relative;
  }
  return root.endsWith('/') ? '$root$relative' : '$root/$relative';
}

String _truncate(String text, int max) {
  if (text.length <= max) {
    return text;
  }
  return '${text.substring(0, max)}\n……（章节记忆过长，已截断）';
}

/// 设定记忆提炼指令：要求严格输出四个二级分类，只提炼已出现信息，不编造。
const _settingMemorySystemPrompt = '''
你是一位资深的小说设定提炼师。请阅读用户提供的「章节记忆」（逐章摘要），从中提炼出
本书的结构化设定文档。

请严格按以下 Markdown 结构输出，只输出这四个二级章节，不要添加任何解释、前言或结尾：

## 人物
### 角色名
- 身份：…
- 性格/特征：…
- 与主线的关系：…

## 地点
### 地点名
- 类型：…
- 说明：…

## 时间线
### 事件或时间段
- 章节：第X章
- 说明：…

## 伏笔
### 伏笔名
- 埋设章节：第X章
- 内容：…
- 当前状态：未回收/已回收（按章节记忆判断）

要求：
- 只提炼章节记忆中已出现的信息，不要虚构、补全或推断未出现的内容。
- 同名人物合并为一条，不重复列出；同一人物的称呼/别名变化在条目内说明。
- 伏笔条目必须标注埋设章节（来自章节记忆）。
- 每个条目用 1~3 行 `- 字段：值` 描述，保持简洁。''';
