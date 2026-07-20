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
    required List<ParsedSection> sections,
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

    // 遍历区段：根章节与卷交错作为正文的直接子节点，共用 bodyChildOrder；
    // 章节编号全局连续（chapSeq），卷编号 volSeq；卷内章节 order 按卷内独立计数。
    final nodes = <ContentNode>[];
    var bodyChildOrder = 1000;
    var volumeSeq = 0;
    var chapterSeq = 0;
    for (final section in sections) {
      if (section is ParsedRootChapters) {
        for (final chapter in section.chapters) {
          chapterSeq += 1;
          final fileName = _chapterFileName(
            chapterSeq,
            chapter.subtitle,
            extension,
          );
          final fileContent = _chapterFileContent(
            chapterSeq,
            chapter,
            chapterFormat,
          );
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
              relativePath: _relativePath(root, target),
              order: bodyChildOrder,
              number: chapterSeq,
              role: ContentRole.normal,
              characterCount: characterCountOf(fileContent),
            ),
          );
          bodyChildOrder += 1000;
        }
      } else if (section is ParsedVolume) {
        volumeSeq += 1;
        final volumeName = ChapterTitleText.sanitizeForFilename(section.name);
        final volumeDirName = volumeName.isEmpty
            ? '第$volumeSeq卷'
            : '第$volumeSeq卷 $volumeName';
        final volumePath = bodyPath.child(volumeDirName);
        await storage.createDirectory(volumePath);
        final volumeId = ContentId(idGenerator.generate());
        nodes.add(
          ContentNode(
            id: volumeId,
            type: ContentNodeType.volume,
            parentId: bodyId,
            relativePath: _relativePath(root, volumePath),
            order: bodyChildOrder,
            number: volumeSeq,
            role: ContentRole.normal,
          ),
        );
        bodyChildOrder += 1000;
        var chapterOrder = 1000;
        for (final chapter in section.chapters) {
          chapterSeq += 1;
          final fileName = _chapterFileName(
            chapterSeq,
            chapter.subtitle,
            extension,
          );
          final fileContent = _chapterFileContent(
            chapterSeq,
            chapter,
            chapterFormat,
          );
          final target = volumePath.child(fileName);
          await storage.createFile(
            target,
            Uint8List.fromList(utf8.encode(fileContent)),
          );
          nodes.add(
            ContentNode(
              id: ContentId(idGenerator.generate()),
              type: ContentNodeType.chapter,
              parentId: volumeId,
              relativePath: _relativePath(root, target),
              order: chapterOrder,
              number: chapterSeq,
              role: ContentRole.normal,
              characterCount: characterCountOf(fileContent),
            ),
          );
          chapterOrder += 1000;
        }
      }
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

  /// 章节文件名：`第{seq}章 [副标题].txt`（副标题 sanitize 后为空则省略）。
  String _chapterFileName(int seq, String subtitle, String extension) {
    final sanitized = ChapterTitleText.sanitizeForFilename(subtitle);
    return sanitized.isEmpty
        ? '第$seq章$extension'
        : '第$seq章 $sanitized$extension';
  }

  /// 章节文件内容：首行标题 + 正文。text 首行为 `第N章 [副标题]`，
  /// markdown 首行为 `# 第N章 [副标题]`。
  String _chapterFileContent(
    int seq,
    NovelChapterImport chapter,
    ChapterFormat format,
  ) {
    final sanitized = ChapterTitleText.sanitizeForFilename(chapter.subtitle);
    final titleLine = ChapterTitleText.titleLine(seq, sanitized);
    return format == ChapterFormat.text
        ? '$titleLine\n${chapter.body}'
        : '# $titleLine\n${chapter.body}';
  }

  /// [target] 相对小说根 [root] 的路径（去掉「根/」前缀），用于
  /// [ContentNode.relativePath]。集中一处避免三处重复的 substring 脆弱算术。
  String _relativePath(LogicalPath root, LogicalPath target) {
    return target.value.substring(root.value.length + 1);
  }
}
