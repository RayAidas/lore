part of '../storage_backed_library_repository.dart';

/// TXT 导入支持：在 [StorageBackedLibraryRepository] 上提供 [importNovel]。
///
/// 单独成 part 文件以控制主仓库文件行数。`on _StorageBackedLibrarySupport`
/// 使其可复用 `_validName`/`_writeNewJson`/`_novelToJson`/`_contentToJson`/
/// `_addRegistration`/`_novelEntry` 等私有助手与 `storageFactory`/`idGenerator`/
/// `clock` 抽象 getter（与其它 support mixin 同一约束模式）。
mixin _StorageBackedImportSupport on _StorageBackedLibrarySupport {
  Future<NovelStructureMutation> importNovel(
    LibraryAccess access, {
    required String title,
    required List<NovelChapterImport> chapters,
    ChapterFormat chapterFormat = ChapterFormat.text,
  }) async {
    final storage = await storageFactory.open(access);
    final validTitle = _validName(title);
    final root = LogicalPath.parse(validTitle);
    // 目录已存在（同名小说）→ alreadyExists，交由 UI 重命名循环。
    if (await storage.stat(root) != null) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.alreadyExists,
          message: '同名小说已存在，请重命名后再导入。',
        ),
      );
    }
    await storage.createDirectory(root);
    await storage.createDirectory(root.child('.lore'));
    final bodyPath = root.child('正文');
    await storage.createDirectory(bodyPath);
    final extension = chapterFormat == ChapterFormat.text ? '.txt' : '.md';
    final now = clock.nowUtc();
    final bodyId = ContentId(idGenerator.generate());
    final metadata = NovelMetadata(
      schemaVersion: 2,
      revision: 0,
      id: NovelId(idGenerator.generate()),
      title: validTitle,
      description: '',
      coverPath: null,
      body: NovelBody(id: bodyId, relativePath: '正文'),
      chapterFormat: chapterFormat,
      numberingMode: NumberingMode.continuous,
      createdAt: now,
      updatedAt: now,
    );

    // 扁平建章：全部直接挂在正文下、顺序编号 1..N、role=normal。
    // 文件名 = `第{seq}章[ {副标题}]{ext}`；seq 唯一保证文件名天然不冲突。
    final nodes = <ContentNode>[];
    for (var index = 0; index < chapters.length; index++) {
      final chapter = chapters[index];
      final seq = index + 1;
      final sanitized = ChapterTitleText.sanitizeForFilename(chapter.subtitle);
      final fileName = sanitized.isEmpty
          ? '第$seq章$extension'
          : '第$seq章 $sanitized$extension';
      final titleLine = ChapterTitleText.titleLine(seq, sanitized);
      final fileContent = chapterFormat == ChapterFormat.text
          ? '$titleLine\n${chapter.body}'
          : '# $titleLine\n${chapter.body}';
      final target = bodyPath.child(fileName);
      await storage.createFile(
        target,
        Uint8List.fromList(utf8.encode(fileContent)),
      );
      nodes.add(
        ContentNode(
          id: ContentId(idGenerator.generate()),
          type: ContentNodeType.chapter,
          parentId: bodyId,
          relativePath: target.value.substring(root.value.length + 1),
          order: seq * 1000,
          number: seq,
          role: ContentRole.normal,
          characterCount: characterCountOf(fileContent),
        ),
      );
    }

    final tree = ContentTree(
      schemaVersion: 2,
      novelId: metadata.id,
      revision: 0,
      nodes: nodes,
    );
    await _writeNewJson(
      storage,
      root.child('.lore').child('novel.json'),
      _novelToJson(metadata),
    );
    await _writeNewJson(
      storage,
      root.child('.lore').child('content.json'),
      _contentToJson(tree),
    );
    await _addRegistration(
      storage,
      NovelRegistration(id: metadata.id, relativePath: root.value),
    );
    final snapshot = NovelSnapshot(
      rootPath: root.value,
      metadata: metadata,
      contentTree: tree,
    );
    return NovelStructureMutation(
      snapshot: snapshot,
      entry: _novelEntry(snapshot),
    );
  }
}
