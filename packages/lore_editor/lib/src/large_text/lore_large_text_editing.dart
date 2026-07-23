part of 'lore_large_text_editor.dart';

/// 用 EditableText 自己的 span 管线渲染查找背景，避免另起 TextPainter 后与实际
/// 输入控件在中文字体回退、换行等场景出现字形位置漂移。
final class _FindHighlightTextEditingController extends TextEditingController {
  _FindHighlightTextEditingController({super.text});

  List<TextAnnotation> _findHighlights = const [];

  void setFindHighlights(List<TextAnnotation> value) {
    if (listEquals(value, _findHighlights)) return;
    _findHighlights = List.of(value);
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final source = value.text;
    // 交给基类处理 IME composing 下划线；输入提交后会立即恢复查找高亮。
    if (_findHighlights.isEmpty ||
        (withComposing &&
            value.composing.isValid &&
            !value.composing.isCollapsed)) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final children = <InlineSpan>[];
    var cursor = 0;
    for (final highlight in _findHighlights) {
      final start = highlight.start.clamp(cursor, source.length);
      final end = highlight.end.clamp(start, source.length);
      if (start > cursor) {
        children.add(TextSpan(text: source.substring(cursor, start)));
      }
      if (end > start) {
        children.add(
          TextSpan(
            text: source.substring(start, end),
            style: TextStyle(backgroundColor: highlight.background),
          ),
        );
      }
      cursor = end;
    }
    if (cursor < source.length) {
      children.add(TextSpan(text: source.substring(cursor)));
    }
    return TextSpan(style: style, children: children);
  }
}

/// 段首自动缩进：当输入在文本里净新增内容、且新增片段含 `\n` 时，把每个
/// 未紧跟缩进的 `\n` 展开为 `\n　　`（两个全角空格 U+3000），让新段落段首
/// 自带两字缩进。仅在 [EditorStyle.firstLineIndent] 开启时由编辑器挂载。
///
/// 选择在 formatter 层而非 controller 层做：formatter 同步把字段文本扩成
/// `甲\n　　乙`，[TextEditingController] 的 diff 直接读到展开后的文本与正确
/// 光标位置（字段即真相），避免"字段/模型不一致 + 光标落在缩进前"的偏移 bug。
/// 删除（含删除既有缩进）不改写；替换且非净增长时也不改写（保守）。
final class _AutoIndentFormatter extends TextInputFormatter {
  const _AutoIndentFormatter();

  static const String _indent = _paragraphIndent; // U+3000 × 2

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final oldText = oldValue.text;
    final newText = newValue.text;
    // 仅在净增长（键入/粘贴）时处理；纯删除或等长替换不改写。
    if (newText.length <= oldText.length) {
      return newValue;
    }
    final minLen = oldText.length;
    var prefix = 0;
    while (prefix < minLen &&
        oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
      prefix += 1;
    }
    var suffix = 0;
    while (suffix < oldText.length - prefix &&
        suffix < newText.length - prefix &&
        oldText.codeUnitAt(oldText.length - suffix - 1) ==
            newText.codeUnitAt(newText.length - suffix - 1)) {
      suffix += 1;
    }
    final insertedStart = prefix;
    final insertedEnd = newText.length - suffix;
    if (insertedEnd <= insertedStart) {
      return newValue;
    }
    final inserted = newText.substring(insertedStart, insertedEnd);
    if (!inserted.contains('\n')) {
      return newValue;
    }
    // 回车落在段首缩进正前方（光标在 block 开头、段首已有两字缩进）：给上方
    // 新拆出的空段补一份缩进，光标 collapsed 在 offset = _indent.length（上方
    // 新段缩进之末、\n 之前），affinity=upstream 确保落上方段。block 内不含
    // '\n'，故「段首」唯一对应 insertedStart == 0；下方原段的缩进由现有「\n 后
    // 紧跟缩进即跳过」逻辑保留，不会重复补。
    if (inserted == '\n' && insertedStart == 0 && oldText.startsWith(_indent)) {
      return TextEditingValue(
        text: '$_indent$newText',
        selection: TextSelection.collapsed(
          offset: _indent.length,
          affinity: TextAffinity.upstream,
        ),
        composing: TextRange.empty,
      );
    }
    // 找出新增片段内的 '\n'，且在【全文】中其后未紧跟 '　　' 的——这些才补缩进。
    // 用全文判定（而非只看 inserted）是为了避免"在已有缩进前按 Enter"产生
    // 　　　　（双重缩进）：若 '\n' 之后本就跟着 '　　'，就不再补。
    final expansions = <int>[];
    for (var i = insertedStart; i < insertedEnd; i += 1) {
      if (newText[i] == '\n' && !newText.startsWith(_indent, i + 1)) {
        expansions.add(i);
      }
    }
    if (expansions.isEmpty) {
      return newValue;
    }
    final buf = StringBuffer();
    var cursor = 0;
    for (final pos in expansions) {
      buf.write(newText.substring(cursor, pos + 1));
      buf.write(_indent);
      cursor = pos + 1;
    }
    buf.write(newText.substring(cursor));
    final rebuilt = buf.toString();
    final delta = expansions.length * _indent.length;

    int remap(int offset) {
      if (offset < 0) {
        return offset;
      }
      if (offset <= insertedStart) {
        return offset;
      }
      if (offset >= insertedEnd) {
        return offset + delta;
      }
      var before = 0;
      for (final pos in expansions) {
        if (pos < offset) {
          before += 1;
        } else {
          break;
        }
      }
      return offset + before * _indent.length;
    }

    final selection = newValue.selection;
    final composing = newValue.composing;
    return TextEditingValue(
      text: rebuilt,
      selection: TextSelection(
        baseOffset: remap(selection.baseOffset),
        extentOffset: remap(selection.extentOffset),
        affinity: selection.affinity,
        isDirectional: selection.isDirectional,
      ),
      composing: composing.isValid && !composing.isCollapsed
          ? TextRange(start: remap(composing.start), end: remap(composing.end))
          : composing,
    );
  }
}
