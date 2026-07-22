import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_editor/lore_editor.dart';
import 'package:path/path.dart' as p;

/// 文档保存状态机所处的阶段。
enum DocumentSaveStatus { clean, dirty, saving, conflict, error }

/// 工作区标签的基类：已打开的文档或待加载的占位。
sealed class WorkspaceTab extends ChangeNotifier {
  String get relativePath;

  String get name => p.basename(relativePath);

  bool get hasUnsavedChanges;
}

/// 会话恢复时尚未加载的文档占位；激活时才真正读取磁盘。
final class DeferredDocument extends WorkspaceTab {
  DeferredDocument({required this.state, required this.format});

  WorkspaceDocumentState state;
  final DocumentFormat format;

  @override
  String get relativePath => state.relativePath;

  @override
  bool get hasUnsavedChanges => false;
}

/// 已打开的文档：持有编辑器控制器、快照、保存/冲突状态等。
final class OpenDocument extends WorkspaceTab {
  OpenDocument({
    required this.snapshot,
    required this.editorController,
    required this.scrollController,
  });

  DocumentSnapshot snapshot;
  final LoreDocumentController editorController;
  final ScrollController scrollController;
  DocumentSaveStatus saveStatus = DocumentSaveStatus.clean;
  DocumentSnapshot? conflictSnapshot;
  LibraryFailure? failure;
  bool sourceMissing = false;
  bool showPreview = false;
  Timer? saveTimer;
  Timer? statisticsTimer;
  Future<bool>? saveFuture;
  Timer? titleSyncTimer;
  int characterCount = 0;

  /// 章节标题编号（来自文件首行 `第N章`）。null 表示非章节标题文档（散文件、
  /// 卷目录、Markdown 章节等暂未启用标题栏的情形），此时编辑器持有完整正文。
  int? chapterNumber;

  /// 章节副标题：标题行 `第N章` 之后、由用户编辑的部分（不含锁定前缀与分隔空格）。
  String chapterTitleSubtitle = '';

  /// 副标题是否有未保存改动（与正文控制器的脏标记独立，因副标题不在控制器内）。
  bool titleDirty = false;

  /// 上次历史快照的正文文本（与磁盘一致；null 表示尚未记录）。用于保存后判定
  /// 变更量阈值，避免每次保存都产生快照。
  String? lastHistorySnapshotText;

  @override
  String get relativePath => snapshot.ref.relativePath;

  DocumentFormat get format => snapshot.ref.format;

  bool get isMarkdown => format == DocumentFormat.markdown;

  @override
  bool get hasUnsavedChanges =>
      editorController.hasUnsavedChanges || titleDirty;

  void notifyChanged() => notifyListeners();

  @override
  void dispose() {
    saveTimer?.cancel();
    statisticsTimer?.cancel();
    titleSyncTimer?.cancel();
    editorController.dispose();
    scrollController.dispose();
    super.dispose();
  }
}
