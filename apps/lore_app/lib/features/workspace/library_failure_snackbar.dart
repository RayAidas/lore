import 'package:flutter/material.dart';
import 'package:lore_application/lore_application.dart';

/// 将 [LibraryFailure] 以 SnackBar 形式展示在 [context] 所属的 Scaffold 上。
///
/// 调用方需先确认 `mounted` / `context.mounted`，再调用本函数。
void showLibraryFailure(BuildContext context, LibraryFailure failure) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(failure.message)));
}
