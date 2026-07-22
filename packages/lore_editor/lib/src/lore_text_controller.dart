import 'package:flutter/widgets.dart';

import 'document_controller.dart';

final class LoreTextController extends TextEditingController
    implements LoreDocumentController {
  LoreTextController({required String text}) : super(text: text) {
    _recomputeCharacterCount(text);
  }

  var _editVersion = 0;
  var _savedVersion = 0;
  int _characterCount = 0;

  static final RegExp _whitespace = RegExp(r'\s+');

  @override
  int get editVersion => _editVersion;

  @override
  int get savedVersion => _savedVersion;

  @override
  bool get hasUnsavedChanges => _editVersion != _savedVersion;

  @override
  int get characterCount => _characterCount;

  void _recomputeCharacterCount(String text) {
    _characterCount = text.replaceAll(_whitespace, '').runes.length;
  }

  @override
  int characterCountInRange(int start, int end) {
    if (end <= start) {
      return 0;
    }
    RangeError.checkValidRange(start, end, text.length);
    // 与 [characterCount] 同口径（去 \s 后按 rune 计），保证全选时二者相等。
    return text.substring(start, end).replaceAll(_whitespace, '').runes.length;
  }

  @override
  int get length => text.length;

  @override
  bool get canUndo => false;

  @override
  bool get canRedo => false;

  @override
  EditorTextSnapshot buildSnapshot() {
    return EditorTextSnapshot(text: text, version: _editVersion);
  }

  @override
  void markSaved(int version) {
    if (version > _savedVersion) {
      _savedVersion = version;
      // 与 LoreLargeTextController 对齐：保存成功后让监听方刷新"已保存"标记。
      notifyListeners();
    }
  }

  @override
  void replaceFromDisk(
    String text, {
    TextSelection? selection,
    bool markSaved = true,
  }) {
    final nextSelection =
        selection ??
        TextSelection.collapsed(offset: text.length.clamp(0, text.length));
    _editVersion += 1;
    if (markSaved) {
      _savedVersion = _editVersion;
    }
    _recomputeCharacterCount(text);
    super.value = TextEditingValue(
      text: text,
      selection: _clampSelection(nextSelection, text.length),
    );
  }

  @override
  void replaceAllText(String text, {TextSelection? selection}) {
    value = TextEditingValue(
      text: text,
      selection: _clampSelection(
        selection ?? TextSelection.collapsed(offset: text.length),
        text.length,
      ),
    );
  }

  @override
  void undo() {}

  @override
  void redo() {}

  @override
  set value(TextEditingValue newValue) {
    final textChanged = newValue.text != value.text;
    if (textChanged) {
      _editVersion += 1;
      _recomputeCharacterCount(newValue.text);
    }
    super.value = newValue;
  }

  TextSelection _clampSelection(TextSelection selection, int textLength) {
    return TextSelection(
      baseOffset: selection.baseOffset.clamp(0, textLength),
      extentOffset: selection.extentOffset.clamp(0, textLength),
      affinity: selection.affinity,
      isDirectional: selection.isDirectional,
    );
  }
}
