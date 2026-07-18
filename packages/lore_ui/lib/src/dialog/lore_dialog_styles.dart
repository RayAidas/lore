import 'package:flutter/material.dart';

/// 对话框主操作按钮（确认 / 保存）样式：方圆角、40 高、紧凑字重。
///
/// 替代默认的胶囊形 FilledButton，使对话框按钮更方正精致，与 Lore 的整体
/// 圆角语言一致。[destructive] 为真时使用错误色（如「永久删除」）。
///
/// 注意：minimumSize 用 `Size(0, 40)` 而非 `Size.fromHeight(40)`——后者会把
/// 宽度设为 `infinity`，导致每个按钮都想占满整行，Actions 的 OverflowBar
/// 因此退化为上下纵排。
ButtonStyle loreDialogPrimaryButton(
  ColorScheme colorScheme, {
  bool destructive = false,
}) {
  return FilledButton.styleFrom(
    backgroundColor: destructive ? colorScheme.error : null,
    foregroundColor: destructive ? colorScheme.onError : null,
    minimumSize: const Size(0, 40),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 18),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
  );
}

/// 对话框次操作按钮（取消）样式：低调文字按钮、40 高，与主按钮等高对齐。
ButtonStyle loreDialogSecondaryButton(ColorScheme colorScheme) {
  return TextButton.styleFrom(
    foregroundColor: colorScheme.onSurfaceVariant,
    minimumSize: const Size(0, 40),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
  );
}
