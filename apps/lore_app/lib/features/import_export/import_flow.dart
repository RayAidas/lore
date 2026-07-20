import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_ui/lore_ui.dart';

import '../workspace/library_failure_snackbar.dart';
import '../workspace/workspace_controller.dart';

/// 导入 TXT 小说的完整流程：选文件 → 解码拆章 → 重名循环重命名 → 写入书库。
///
/// 重逻辑从侧栏外移到此，保持 [LibrarySidebar] 精简。所有失败统一经
/// [showLibraryFailure] 提示；用户在任意弹窗取消则静默退出。
Future<void> importTxtNovelFlow(
  BuildContext context,
  WorkspaceController controller,
) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['txt'],
    allowMultiple: false,
  );
  final files = result?.files ?? const <PlatformFile>[];
  if (files.isEmpty) {
    return;
  }
  if (!context.mounted) {
    return;
  }
  final file = files.first;
  final bytes = await _readFileBytes(file);
  if (!context.mounted) {
    return;
  }
  if (bytes == null) {
    _failure(
      context,
      const LibraryFailure(code: LibraryFailureCode.io, message: '无法读取所选文件。'),
    );
    return;
  }
  final text = _decodeTxt(bytes);
  final parsed = TxtNovelParser.parse(text: text, fileName: file.name);
  if (parsed.chapters.isEmpty) {
    _failure(
      context,
      const LibraryFailure(
        code: LibraryFailureCode.unsupportedFormat,
        message: '文件内容为空，未解析到任何章节。',
      ),
    );
    return;
  }
  if (!context.mounted) {
    return;
  }

  var title = parsed.titleSuggestion.isNotEmpty
      ? parsed.titleSuggestion
      : _stem(file.name);
  if (title.isEmpty) {
    title = '导入小说';
  }

  // 重名循环：弹输入框直到无重名或用户取消。
  while (controller.novelTitleExists(title)) {
    if (!context.mounted) {
      return;
    }
    final renamed = await showLoreTextPromptDialog(
      context: context,
      title: '书名重复',
      label: '请输入新书名',
      initialValue: title,
      helperText: '书库中已存在同名小说，请改名后继续。',
    );
    if (!context.mounted || renamed == null) {
      return;
    }
    final next = renamed.trim();
    if (next.isEmpty) {
      continue;
    }
    title = next;
  }
  if (!context.mounted) {
    return;
  }

  final count = parsed.chapters.length;
  try {
    await controller.importNovel(title: title, chapters: parsed.chapters);
  } on LibraryOperationException catch (error) {
    if (!context.mounted) {
      return;
    }
    _failure(context, error.failure);
    return;
  }
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('已导入「$title」，共 $count 章。')));
}

Future<Uint8List?> _readFileBytes(PlatformFile file) async {
  final path = file.path;
  if (path != null) {
    try {
      return Uint8List.fromList(await File(path).readAsBytes());
    } on Exception {
      return file.bytes;
    }
  }
  return file.bytes;
}

/// 解码 TXT：剥 UTF-8 BOM，容错解码非法字节。
String _decodeTxt(Uint8List bytes) {
  final body =
      bytes.length >= 3 &&
          bytes[0] == 0xEF &&
          bytes[1] == 0xBB &&
          bytes[2] == 0xBF
      ? bytes.sublist(3)
      : bytes;
  return utf8.decode(body, allowMalformed: true);
}

String _stem(String fileName) {
  var stem = fileName;
  final slash = stem.lastIndexOf(RegExp(r'[/\\]'));
  if (slash >= 0) {
    stem = stem.substring(slash + 1);
  }
  final dot = stem.lastIndexOf('.');
  if (dot > 0) {
    stem = stem.substring(0, dot);
  }
  return stem;
}

void _failure(BuildContext context, LibraryFailure failure) {
  if (!context.mounted) {
    return;
  }
  showLibraryFailure(context, failure);
}
