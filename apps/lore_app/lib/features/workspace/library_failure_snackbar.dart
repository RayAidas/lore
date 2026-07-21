import 'package:flutter/material.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_ui/lore_ui.dart';

/// 将 [LibraryFailure] 以 Toast（[LoreToast] error 态）形式展示在 [context]
/// 所属的根 Overlay 顶部。
///
/// 调用方需先确认 `mounted` / `context.mounted`，再调用本函数。
void showLibraryFailure(BuildContext context, LibraryFailure failure) {
  LoreToast.error(context, failure.message);
}
