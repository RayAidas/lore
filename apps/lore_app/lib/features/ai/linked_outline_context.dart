import 'package:lore_domain/lore_domain.dart';
import 'package:path/path.dart' as p;

import '../workspace/workspace_controller.dart';

/// 把当前小说已关联的大纲合并成发送给模型的参考文本（每个文件带文件名头）。
///
/// 文件缺失/读取失败时跳过，不阻断主请求；无关联时返回空串。
/// 写作助手与大纲生成面板共用，避免两处重复实现。
Future<String> buildLinkedOutlineReference({
  required WorkspaceController controller,
  required NovelOutlineLinks? links,
}) async {
  final novel = controller.activeNovel;
  if (novel == null) {
    return '';
  }
  final paths = links?.forNovel(novel.metadata.id.value) ?? const <String>[];
  if (paths.isEmpty) {
    return '';
  }
  final parts = <String>[];
  for (final path in paths) {
    try {
      final doc = await controller.service.readDocument(
        controller.session,
        DocumentRef(relativePath: path, format: DocumentFormat.markdown),
      );
      final text = doc.text.trim();
      if (text.isNotEmpty) {
        parts.add('【${p.basename(path)}】\n$text');
      }
    } catch (_) {
      // 大纲被删或读取失败：跳过。
    }
  }
  return parts.join('\n\n');
}
