import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:test/test.dart';

/// 按序返回预设文本、记录每次调用参数的假客户端。
final class _FakeAiChatClient implements AiChatClient {
  _FakeAiChatClient(this._responses);

  final List<String> _responses;
  final List<({List<AiChatMessage> messages, Duration timeout})> calls = [];
  Object? nextError;

  @override
  Future<String> completeChat({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<AiChatMessage> messages,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final error = nextError;
    if (error != null) {
      throw error;
    }
    calls.add((messages: messages, timeout: timeout));
    return _responses.removeAt(0);
  }
}

/// 按路径返回预设文本的假文档仓储；缺失路径抛 notFound。
final class _FakeDocumentRepository implements DocumentRepository {
  _FakeDocumentRepository(this._texts);

  final Map<String, String> _texts;

  @override
  Future<DocumentSnapshot> readDocument(
    LibraryAccess access,
    DocumentRef ref,
  ) async {
    final text = _texts[ref.relativePath];
    if (text == null) {
      throw const LibraryOperationException(
        LibraryFailure(code: LibraryFailureCode.notFound, message: 'missing'),
      );
    }
    return DocumentSnapshot(
      ref: ref,
      text: text,
      encoding: TextEncoding.utf8,
      lineEnding: LineEnding.lf,
      revision: const DocumentRevision('rev'),
    );
  }

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  const novelId = NovelId('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
  const bodyId = ContentId('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');

  final session = LibrarySession(
    access: const LibraryAccess(
      token: '/tmp/lib',
      displayPath: '/tmp/lib',
      isPending: false,
    ),
    metadata: LibraryMetadata(
      schemaVersion: 1,
      id: const LibraryId('lib'),
      createdAt: DateTime.utc(2026, 7, 17),
      updatedAt: DateTime.utc(2026, 7, 17),
    ),
  );

  // 设定记忆只读「小说记忆.md」，内容树与本测试无关，恒为空。
  NovelSnapshot snapshot() => NovelSnapshot(
    rootPath: 'novel',
    metadata: NovelMetadata(
      schemaVersion: 1,
      id: novelId,
      title: 'novel',
      description: '',
      coverPath: null,
      body: const NovelBody(id: bodyId, relativePath: '正文'),
      chapterFormat: ChapterFormat.markdown,
      numberingMode: NumberingMode.continuous,
      createdAt: DateTime.utc(2026, 7, 17),
      updatedAt: DateTime.utc(2026, 7, 17),
    ),
    contentTree: const ContentTree(
      schemaVersion: 1,
      novelId: novelId,
      revision: 1,
      nodes: [],
    ),
  );

  const config = WritingAgentConfig(
    schemaVersion: WritingAgentConfig.schemaVersionCurrent,
    baseUrl: 'https://example.com/v1',
    model: 'test-model',
    enabled: true,
  );
  const apiKey = 'sk-test';

  const memoryText = '# 章节记忆\n> 基于 2 章生成 · 2026-08-13\n\n'
      '## 第1章 觉醒\n林晚在黎明醒来。\n\n## 第2章 相遇\n她在桥头出现。';

  test('throws when the chapter memory doc is missing', () async {
    final service = SettingMemoryGenerationService(
      client: _FakeAiChatClient([]),
      documentRepository: _FakeDocumentRepository(const {}),
    );

    await expectLater(
      service.generateSettingMemory(
        session: session,
        novel: snapshot(),
        config: config,
        apiKey: apiKey,
      ),
      throwsA(
        isA<AiRequestException>().having(
          (e) => e.message,
          'message',
          contains('请先生成章节记忆'),
        ),
      ),
    );
  });

  test('throws when the chapter memory doc is blank', () async {
    final service = SettingMemoryGenerationService(
      client: _FakeAiChatClient([]),
      documentRepository: _FakeDocumentRepository({
        'novel/小说记忆.md': '   \n',
      }),
    );

    await expectLater(
      service.generateSettingMemory(
        session: session,
        novel: snapshot(),
        config: config,
        apiKey: apiKey,
      ),
      throwsA(isA<AiRequestException>()),
    );
  });

  test('generates a setting memory doc from the full chapter memory', () async {
    final client = _FakeAiChatClient(['## 人物\n### 林晚\n- 身份：主角']);
    final service = SettingMemoryGenerationService(
      client: client,
      documentRepository: _FakeDocumentRepository({
        'novel/小说记忆.md': memoryText,
      }),
    );

    final result = await service.generateSettingMemory(
      session: session,
      novel: snapshot(),
      config: config,
      apiKey: apiKey,
    );

    // 头部由 Service 固定生成（不经模型）。
    expect(result, startsWith('# 设定记忆\n> 基于章节记忆生成'));
    expect(result, contains('## 人物'));
    expect(result, contains('### 林晚'));
    // 单次调用、超时与章节记忆一致。
    expect(client.calls, hasLength(1));
    expect(client.calls.single.timeout, const Duration(seconds: 180));
    final messages = client.calls.single.messages;
    expect(messages[0].role, AiChatRole.system);
    expect(messages[0].content, isNotEmpty);
    expect(messages[1].role, AiChatRole.user);
    // 章节记忆全文进入用户消息。
    expect(messages[1].content, contains('## 第1章 觉醒'));
    expect(messages[1].content, contains('林晚在黎明醒来。'));
  });

  test('truncates an overlong chapter memory with a marker', () async {
    final client = _FakeAiChatClient(['## 人物\n### 林晚']);
    final service = SettingMemoryGenerationService(
      client: client,
      documentRepository: _FakeDocumentRepository({
        'novel/小说记忆.md': '字' * 40000,
      }),
    );

    await service.generateSettingMemory(
      session: session,
      novel: snapshot(),
      config: config,
      apiKey: apiKey,
    );

    final user = client.calls.single.messages[1].content;
    expect(user, contains('章节记忆过长，已截断'));
    expect(user.length, lessThan(40000 + 200));
  });

  test('wraps unexpected model errors as AiRequestException', () async {
    final client = _FakeAiChatClient(['x'])..nextError = StateError('boom');
    final service = SettingMemoryGenerationService(
      client: client,
      documentRepository: _FakeDocumentRepository({
        'novel/小说记忆.md': memoryText,
      }),
    );

    await expectLater(
      service.generateSettingMemory(
        session: session,
        novel: snapshot(),
        config: config,
        apiKey: apiKey,
      ),
      throwsA(
        isA<AiRequestException>().having(
          (e) => e.message,
          'message',
          contains('生成设定记忆失败'),
        ),
      ),
    );
  });
}
