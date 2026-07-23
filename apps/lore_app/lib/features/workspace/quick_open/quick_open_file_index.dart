import 'package:lore_domain/lore_domain.dart';

import '../workspace_controller.dart';

const String _txtExtension = '.txt';

/// 展示名:文本文件隐藏 `.txt` 后缀(大小写不敏感,与目录树规则一致),
/// 其余条目保留原文件名。规则复制自
/// `workspace_directory_tree.dart` 的 `_treeDisplayName`(私有,无法直接复用),
/// 未来可提炼为共享 helper 消除重复。
String displayName(LibraryEntry entry) {
  final name = entry.name;
  if (entry.type == LibraryEntryType.textFile &&
      name.length > _txtExtension.length &&
      name.toLowerCase().endsWith(_txtExtension)) {
    return name.substring(0, name.length - _txtExtension.length);
  }
  return name;
}

/// 递归遍历工作区文件树,收集所有可打开文件(`.txt`/`.md`),
/// 排除目录与 `otherFile`,按展示名排序返回。
///
/// `listChildren` 一次只返回一层([WorkspaceController.listChildren]),
/// 故从此处串行深度优先递归整棵树。小说项目文件量有限,串行足够;面板仅在
/// 唤起时遍历一次,关闭即丢弃缓存。
Future<List<LibraryEntry>> collectOpenableFiles(
  WorkspaceController controller,
) async {
  final out = <LibraryEntry>[];
  final visited = <String>{};
  Future<void> walk(String dir) async {
    // 符号链接环 / 重复路径保护:同一 relativePath 只走一次。
    if (!visited.add(dir)) return;
    final children = await controller.listChildren(relativePath: dir);
    for (final entry in children) {
      if (entry.isDirectory) {
        await walk(entry.relativePath);
      } else if (entry.type != LibraryEntryType.otherFile) {
        out.add(entry);
      }
    }
  }

  await walk('');
  out.sort((a, b) => displayName(a).compareTo(displayName(b)));
  return out;
}
