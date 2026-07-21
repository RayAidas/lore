import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_ui/lore_ui.dart';

import '../workspace/library_failure_snackbar.dart';
import '../workspace/workspace_controller.dart';
import 'txt_decoding.dart';

/// 导入 TXT 小说的完整流程：选文件 → 解码拆章 → 重名循环重命名 → 写入书库。
///
/// 重逻辑从侧栏外移到此，保持 [LibrarySidebar] 精简。所有失败统一经
/// [showLibraryFailure] 提示；用户在任意弹窗取消则静默退出。
Future<void> importTxtNovelFlow(
  BuildContext context,
  WorkspaceController controller,
) async {
  // file_picker 在 macOS 缺 entitlement 等底层异常时会抛 PlatformException，
  // 统一兜底成友好提示，避免未捕获异常导致红屏。
  FilePickerResult? result;
  try {
    result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt'],
      allowMultiple: false,
    );
  } on PlatformException {
    if (!context.mounted) {
      return;
    }
    _failure(
      context,
      const LibraryFailure(code: LibraryFailureCode.io, message: '无法打开文件选择器。'),
    );
    return;
  }
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
  final String text;
  try {
    text = await decodeTxtBytes(bytes);
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
  final parsed = TxtNovelParser.parse(text: text, fileName: file.name);
  final count = _totalChapters(parsed);
  if (count == 0) {
    _failure(
      context,
      const LibraryFailure(
        code: LibraryFailureCode.unsupportedFormat,
        message: '文件内容为空。',
      ),
    );
    return;
  }

  var title = parsed.titleSuggestion.isNotEmpty
      ? parsed.titleSuggestion
      : _stem(file.name);
  if (title.isEmpty) {
    title = '导入小说';
  }

  // 重名处理：内存预检 + 写入兜底构成循环。写入时若仍撞 alreadyExists
  // （预检与写入之间的竞态、或内存列表未同步），回到重命名弹窗重试，而非
  // 直接报错让用户从头来。
  while (true) {
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
    try {
      await controller.importNovel(title: title, sections: parsed.sections);
      break;
    } on LibraryOperationException catch (error) {
      if (!context.mounted) {
        return;
      }
      if (error.failure.code != LibraryFailureCode.alreadyExists) {
        _failure(context, error.failure);
        return;
      }
      // alreadyExists：循环回到重命名弹窗，用当前 title 作初值重试。
    }
  }
  if (!context.mounted) {
    return;
  }
  LoreToast.show(
    context,
    message: '已导入「$title」，共 $count 章。',
    type: LoreToastType.success,
    duration: const Duration(seconds: 3),
  );
}

int _totalChapters(ParsedTxtNovel parsed) {
  var total = 0;
  for (final section in parsed.sections) {
    total += switch (section) {
      ParsedRootChapters(:final chapters) => chapters.length,
      ParsedVolume(:final chapters) => chapters.length,
    };
  }
  return total;
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
