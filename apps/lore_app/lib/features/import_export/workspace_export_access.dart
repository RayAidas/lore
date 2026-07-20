import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:path/path.dart' as p;

import '../workspace/workspace_controller.dart';

/// 导出场景对 [WorkspaceController] 的只读访问扩展。
///
/// 把「加载小说快照 / 读章节正文」这两段导出专用逻辑从控制器外移到扩展，
/// 控制主控制器文件行数；两者都只依赖控制器公开字段（[WorkspaceController.service]、
/// [WorkspaceController.session]、[WorkspaceController.novelStructureService]）。
extension WorkspaceExportAccess on WorkspaceController {
  /// 加载小说快照（导出面板用于枚举卷/章）。每次现读以保证最新结构。
  Future<NovelSnapshot> loadNovelSnapshot(NovelId novelId) async {
    final service = novelStructureService;
    if (service == null) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.platformUnsupported,
          message: '当前环境不支持读取小说结构。',
        ),
      );
    }
    return service.loadNovel(session, novelId: novelId);
  }

  /// 读取章节文件的完整文本（含首行标题），供导出拆标题/正文。只读、不触碰
  /// 已开标签页与 content.json。
  Future<String> readChapterRawText(
    NovelSnapshot novel,
    ContentNode chapter,
  ) async {
    final ref = DocumentRef(
      relativePath: p.posix.join(novel.rootPath, chapter.relativePath),
      format: novel.metadata.chapterFormat == ChapterFormat.text
          ? DocumentFormat.text
          : DocumentFormat.markdown,
    );
    final document = await service.readDocument(session, ref);
    return document.text;
  }
}
