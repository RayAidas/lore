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

/// 按路径返回预设章节文本的假文档仓储；缺失路径抛 notFound。
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

  NovelSnapshot snapshot(List<ContentNode> nodes) => NovelSnapshot(
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
    contentTree: ContentTree(
      schemaVersion: 1,
      novelId: novelId,
      revision: 1,
      nodes: nodes,
    ),
  );

  const config = WritingAgentConfig(
    schemaVersion: WritingAgentConfig.schemaVersionCurrent,
    baseUrl: 'https://example.com/v1',
    model: 'test-model',
    enabled: true,
  );
  const apiKey = 'sk-test';

  test('reads every chapter and wraps result with a fixed header', () async {
    final nodes = [
      const ContentNode(
        id: ContentId('n1'),
        type: ContentNodeType.chapter,
        parentId: bodyId,
        relativePath: '正文/第1章.md',
        order: 1000,
        number: 1,
        role: ContentRole.normal,
      ),
      const ContentNode(
        id: ContentId('n2'),
        type: ContentNodeType.chapter,
        parentId: bodyId,
        relativePath: '正文/第2章.md',
        order: 2000,
        number: 2,
        role: ContentRole.normal,
      ),
    ];
    final client = _FakeAiChatClient([
      '## 第1章 觉醒\n林晚在黎明醒来。\n\n## 第2章 相遇\n她在桥头出现。',
    ]);
    final service = MemoryGenerationService(
      client: client,
      documentRepository: _FakeDocumentRepository({
        'novel/正文/第1章.md': '# 第1章 觉醒\n\n林晚醒来。',
        'novel/正文/第2章.md': '# 第2章 相遇\n\n她出现了。',
      }),
    );

    final result = await service.generateMemory(
      session: session,
      novel: snapshot(nodes),
      config: config,
      apiKey: apiKey,
    );

    // 两章 < 分批上限，单次调用，超时与大纲生成一致。
    expect(client.calls, hasLength(1));
    expect(client.calls.single.timeout, const Duration(seconds: 180));
    final user = client.calls.single.messages[1].content;
    expect(user, contains('### 第1章 觉醒'));
    expect(user, contains('林晚醒来。'));
    expect(user, contains('### 第2章 相遇'));
    expect(user, contains('她出现了。'));
    // 头部由 Service 固定生成（不经模型）。
    expect(result, startsWith('# 章节记忆'));
    expect(result, contains('基于 2 章生成'));
    expect(result, contains('## 第1章 觉醒'));
  });

  test('skips volume nodes and empty title-only chapters', () async {
    final nodes = [
      const ContentNode(
        id: ContentId('vol'),
        type: ContentNodeType.volume,
        parentId: bodyId,
        relativePath: '正文/第一卷',
        order: 1000,
        number: 1,
        role: ContentRole.normal,
      ),
      const ContentNode(
        id: ContentId('c1'),
        type: ContentNodeType.chapter,
        parentId: bodyId,
        relativePath: '正文/第1章.md',
        order: 1000,
        number: 1,
        role: ContentRole.normal,
      ),
      const ContentNode(
        id: ContentId('c2'),
        type: ContentNodeType.chapter,
        parentId: bodyId,
        relativePath: '正文/第2章.md',
        order: 2000,
        number: 2,
        role: ContentRole.normal,
      ),
    ];
    final client = _FakeAiChatClient(['## 第1章 觉醒\n只有一章。']);
    final service = MemoryGenerationService(
      client: client,
      documentRepository: _FakeDocumentRepository({
        // 只有标题行：视为空章跳过。
        'novel/正文/第1章.md': '# 第1章 觉醒',
        'novel/正文/第2章.md': '# 第2章 相遇\n\n真正的正文。',
      }),
    );

    final result = await service.generateMemory(
      session: session,
      novel: snapshot(nodes),
      config: config,
      apiKey: apiKey,
    );

    expect(client.calls, hasLength(1));
    final user = client.calls.single.messages[1].content;
    expect(user, isNot(contains('第1章')));
    expect(user, contains('### 第2章 相遇'));
    expect(result, contains('基于 1 章生成'));
  });

  test('fails gracefully when no written chapters exist', () async {
    final service = MemoryGenerationService(
      client: _FakeAiChatClient([]),
      documentRepository: _FakeDocumentRepository(const {}),
    );

    await expectLater(
      service.generateMemory(
        session: session,
        novel: snapshot(const []),
        config: config,
        apiKey: apiKey,
      ),
      throwsA(
        isA<AiRequestException>().having(
          (e) => e.message,
          'message',
          contains('暂无已写章节'),
        ),
      ),
    );
  });

  test('batches chapters across multiple calls when exceeding the cap',
      () async {
    final nodes = <ContentNode>[];
    final texts = <String, String>{};
    for (var i = 1; i <= 17; i++) {
      nodes.add(
        ContentNode(
          id: ContentId('c$i'),
          type: ContentNodeType.chapter,
          parentId: bodyId,
          relativePath: '正文/第$i章.md',
          order: i * 100,
          number: i,
          role: ContentRole.normal,
        ),
      );
      texts['novel/正文/第$i章.md'] = '# 第$i章 标题$i\n\n第$i章正文';
    }
    final batch1 = StringBuffer();
    for (var i = 1; i <= 15; i++) {
      batch1
        ..writeln('## 第$i章 标题$i')
        ..writeln('摘要$i。');
    }
    final responses = [
      batch1.toString(),
      '## 第16章 标题16\n摘要16。\n\n## 第17章 标题17\n摘要17。',
    ];
    final client = _FakeAiChatClient(responses);
    final service = MemoryGenerationService(
      client: client,
      documentRepository: _FakeDocumentRepository(texts),
    );

    final result = await service.generateMemory(
      session: session,
      novel: snapshot(nodes),
      config: config,
      apiKey: apiKey,
    );

    // 17 章 → 15 + 2 两批。
    expect(client.calls, hasLength(2));
    expect(client.calls[0].messages[1].content, contains('### 第15章 标题15'));
    expect(client.calls[0].messages[1].content, isNot(contains('第16章')));
    final secondUser = client.calls[1].messages[1].content;
    expect(secondUser, contains('### 第16章 标题16'));
    expect(secondUser, contains('### 第17章 标题17'));
    expect(result, contains('基于 17 章生成'));
    // 两批结果直接拼接。
    expect(result, contains('摘要15。'));
    expect(result, contains('摘要17。'));
  });

  test('truncates overlong chapter bodies and marks the cut', () async {
    final longBody = '字' * 1500;
    final nodes = [
      const ContentNode(
        id: ContentId('c1'),
        type: ContentNodeType.chapter,
        parentId: bodyId,
        relativePath: '正文/第1章.md',
        order: 1000,
        number: 1,
        role: ContentRole.normal,
      ),
    ];
    final client = _FakeAiChatClient(['## 第1章 觉醒\n摘要。']);
    final service = MemoryGenerationService(
      client: client,
      documentRepository: _FakeDocumentRepository({
        'novel/正文/第1章.md': '# 第1章 觉醒\n\n$longBody',
      }),
    );

    await service.generateMemory(
      session: session,
      novel: snapshot(nodes),
      config: config,
      apiKey: apiKey,
    );

    final user = client.calls.single.messages[1].content;
    expect(user, contains('……（正文过长，已截断）'));
    expect(user.length, lessThan(1500 + 200));
  });

  test('wraps unexpected read or model errors as AiRequestException', () async {
    final nodes = [
      const ContentNode(
        id: ContentId('c1'),
        type: ContentNodeType.chapter,
        parentId: bodyId,
        relativePath: '正文/第1章.md',
        order: 1000,
        number: 1,
        role: ContentRole.normal,
      ),
    ];
    final client = _FakeAiChatClient(['x'])..nextError = StateError('boom');
    final service = MemoryGenerationService(
      client: client,
      documentRepository: _FakeDocumentRepository({
        'novel/正文/第1章.md': '# 第1章 觉醒\n\n正文',
      }),
    );

    await expectLater(
      service.generateMemory(
        session: session,
        novel: snapshot(nodes),
        config: config,
        apiKey: apiKey,
      ),
      throwsA(isA<AiRequestException>()),
    );
  });
}
