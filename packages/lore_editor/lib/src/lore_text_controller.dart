import 'package:flutter/widgets.dart';

final class EditorTextSnapshot {
  const EditorTextSnapshot({required this.text, required this.version});

  final String text;
  final int version;
}

final class LoreTextController extends TextEditingController {
  LoreTextController({required String text}) : super(text: text);

  var _editVersion = 0;
  var _savedVersion = 0;

  int get editVersion => _editVersion;

  int get savedVersion => _savedVersion;

  bool get hasUnsavedChanges => _editVersion != _savedVersion;

  EditorTextSnapshot buildSnapshot() {
    return EditorTextSnapshot(text: text, version: _editVersion);
  }

  void markSaved(int version) {
    if (version > _savedVersion) {
      _savedVersion = version;
    }
  }

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
    super.value = TextEditingValue(
      text: text,
      selection: _clampSelection(nextSelection, text.length),
    );
  }

  @override
  set value(TextEditingValue newValue) {
    final textChanged = newValue.text != value.text;
    if (textChanged) {
      _editVersion += 1;
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
