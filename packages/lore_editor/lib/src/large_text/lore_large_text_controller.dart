import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../document_controller.dart';
import 'chunked_text_buffer.dart';

final class LargeTextBlock {
  const LargeTextBlock({required this.text, required this.hasLineBreak});

  final String text;
  final bool hasLineBreak;

  int get documentLength => text.length + (hasLineBreak ? 1 : 0);
}

final class LoreLargeTextController extends ChangeNotifier
    implements LoreDocumentController {
  LoreLargeTextController({required String text})
    : _buffer = ChunkedTextBuffer(text) {
    _rebuildBlocks();
    _selection = TextSelection.collapsed(offset: text.length);
  }

  static const _maximumHistoryEntries = 1000;
  static const _maximumHistoryCharacters = 4 * 1024 * 1024;
  static const _typingMergeWindow = Duration(milliseconds: 750);

  ChunkedTextBuffer _buffer;
  final List<LargeTextBlock> _blocks = [];
  late final List<LargeTextBlock> _blocksView = UnmodifiableListView(_blocks);
  final _BlockOffsetIndex _blockOffsets = _BlockOffsetIndex();
  final List<_EditRecord> _undoStack = [];
  final List<_EditRecord> _redoStack = [];
  var _undoStackCharacters = 0;
  late TextSelection _selection;
  var _editVersion = 0;
  var _savedVersion = 0;
  var _blocksRevision = 0;
  var _selectionDragActive = false;

  List<LargeTextBlock> get blocks => _blocksView;

  @override
  String get text => _buffer.text;

  @override
  set text(String value) => replaceAllText(value);

  @override
  TextSelection get selection => _selection;

  @override
  set selection(TextSelection value) {
    final clamped = _clampSelection(value);
    if (clamped == _selection) {
      return;
    }
    _selection = clamped;
    notifyListeners();
  }

  @override
  int get editVersion => _editVersion;

  @override
  int get savedVersion => _savedVersion;

  @override
  int get characterCount => _buffer.characterCount;

  @override
  int get length => _buffer.length;

  int get lineCount => _buffer.lineBreakCount + 1;

  int get blocksRevision => _blocksRevision;

  bool get selectionDragActive => _selectionDragActive;

  void beginSelectionDrag() {
    _selectionDragActive = true;
  }

  void endSelectionDrag() {
    _selectionDragActive = false;
  }

  @override
  bool get hasUnsavedChanges => _editVersion != _savedVersion;

  @override
  bool get canUndo => _undoStack.isNotEmpty;

  @override
  bool get canRedo => _redoStack.isNotEmpty;

  int blockStart(int blockIndex) {
    RangeError.checkValidIndex(blockIndex, _blocks);
    return _blockOffsets.prefixLength(blockIndex);
  }

  int blockIndexForOffset(int offset) {
    RangeError.checkValueInInterval(offset, 0, length);
    return _blockOffsets.indexForOffset(offset, _blocks.length);
  }

  void replaceBlockRange(
    int blockIndex,
    int start,
    int end,
    String replacement,
    TextSelection localSelection,
  ) {
    final block = _blocks[blockIndex];
    RangeError.checkValidRange(start, end, block.text.length);
    final documentBlockStart = blockStart(blockIndex);
    final globalStart = documentBlockStart + start;
    final beforeSelection = _selection;
    final globalEnd = globalStart + end - start;
    final structuralChange =
        replacement.contains('\n') ||
        _buffer.substring(globalStart, globalEnd).contains('\n');
    final change = structuralChange
        ? _replaceRangeAndRebuildBlocks(globalStart, globalEnd, replacement)
        : _buffer.replace(globalStart, globalEnd, replacement);
    _editVersion += 1;
    _selection = TextSelection(
      baseOffset: documentBlockStart + localSelection.baseOffset,
      extentOffset: documentBlockStart + localSelection.extentOffset,
      affinity: localSelection.affinity,
      isDirectional: localSelection.isDirectional,
    );
    _recordEdit(change, beforeSelection, _selection);
    if (!structuralChange) {
      final oldLength = block.documentLength;
      _blocks[blockIndex] = LargeTextBlock(
        text:
            block.text.substring(0, start) +
            replacement +
            block.text.substring(end),
        hasLineBreak: block.hasLineBreak,
      );
      _blockOffsets.update(
        blockIndex,
        _blocks[blockIndex].documentLength - oldLength,
      );
      if (_blocks[blockIndex].text.length >
          ChunkedTextBuffer.targetChunkLength * 2) {
        _rebuildBlocks();
      }
    }
    notifyListeners();
  }

  void replaceSelection(String replacement) {
    final normalized = _selection.isValid
        ? _selection
        : TextSelection.collapsed(offset: length);
    final start = normalized.start;
    final end = normalized.end;
    final beforeSelection = _selection;
    final change = _replaceRangeAndRebuildBlocks(start, end, replacement);
    _editVersion += 1;
    _selection = TextSelection.collapsed(offset: start + replacement.length);
    _recordEdit(change, beforeSelection, _selection);
    notifyListeners();
  }

  void replaceRange(int start, int end, String replacement) {
    final beforeSelection = _selection;
    final change = _replaceRangeAndRebuildBlocks(start, end, replacement);
    _editVersion += 1;
    _selection = TextSelection.collapsed(offset: start + replacement.length);
    _recordEdit(change, beforeSelection, _selection);
    notifyListeners();
  }

  @override
  EditorTextSnapshot buildSnapshot() {
    return EditorTextSnapshot(text: text, version: _editVersion);
  }

  @override
  void markSaved(int version) {
    if (version > _savedVersion) {
      _savedVersion = version;
      notifyListeners();
    }
  }

  @override
  void replaceFromDisk(
    String text, {
    TextSelection? selection,
    bool markSaved = true,
  }) {
    _buffer = ChunkedTextBuffer(text);
    _editVersion += 1;
    if (markSaved) {
      _savedVersion = _editVersion;
    }
    _selection = _clampSelection(
      selection ?? TextSelection.collapsed(offset: text.length),
    );
    _undoStack.clear();
    _redoStack.clear();
    _undoStackCharacters = 0;
    _rebuildBlocks();
    notifyListeners();
  }

  @override
  void replaceAllText(String text, {TextSelection? selection}) {
    final beforeSelection = _selection;
    final change = _replaceRangeAndRebuildBlocks(0, length, text);
    _editVersion += 1;
    _selection = _clampSelection(
      selection ?? TextSelection.collapsed(offset: text.length),
    );
    _recordEdit(change, beforeSelection, _selection);
    notifyListeners();
  }

  @override
  void undo() {
    if (_undoStack.isEmpty) {
      return;
    }
    final edit = _undoStack.removeLast();
    _undoStackCharacters -= edit.insertedText.length + edit.removedText.length;
    _replaceRangeAndRebuildBlocks(
      edit.start,
      edit.start + edit.insertedText.length,
      edit.removedText,
    );
    _redoStack.add(edit);
    _editVersion += 1;
    _selection = _clampSelection(edit.beforeSelection);
    notifyListeners();
  }

  @override
  void redo() {
    if (_redoStack.isEmpty) {
      return;
    }
    final edit = _redoStack.removeLast();
    _replaceRangeAndRebuildBlocks(
      edit.start,
      edit.start + edit.removedText.length,
      edit.insertedText,
    );
    _undoStack.add(edit);
    _undoStackCharacters += edit.insertedText.length + edit.removedText.length;
    _editVersion += 1;
    _selection = _clampSelection(edit.afterSelection);
    notifyListeners();
  }

  void _recordEdit(
    TextBufferChange change,
    TextSelection beforeSelection,
    TextSelection afterSelection,
  ) {
    final now = DateTime.now();
    final previous = _undoStack.lastOrNull;
    if (previous != null &&
        change.removedText.isEmpty &&
        previous.removedText.isEmpty &&
        change.start == previous.start + previous.insertedText.length &&
        now.difference(previous.recordedAt) <= _typingMergeWindow) {
      _undoStack[_undoStack.length - 1] = _EditRecord(
        start: previous.start,
        removedText: '',
        insertedText: previous.insertedText + change.insertedText,
        beforeSelection: previous.beforeSelection,
        afterSelection: afterSelection,
        recordedAt: now,
      );
      _undoStackCharacters += change.insertedText.length;
    } else {
      _undoStack.add(
        _EditRecord(
          start: change.start,
          removedText: change.removedText,
          insertedText: change.insertedText,
          beforeSelection: beforeSelection,
          afterSelection: afterSelection,
          recordedAt: now,
        ),
      );
      _undoStackCharacters +=
          change.insertedText.length + change.removedText.length;
    }
    // 同时按条数和字符总量淘汰：纯条数上限挡不住"粘贴几段超长文本"把历史
    // 撑到上百 MB 的情况。只统计 undo 栈——redo 栈必然来自此前有界的 undo，
    // 且下一次编辑会清空 redo，因此 redo 不会越界。
    while (_undoStack.length > _maximumHistoryEntries ||
        _undoStackCharacters > _maximumHistoryCharacters) {
      if (_undoStack.isEmpty) {
        break;
      }
      final evicted = _undoStack.removeAt(0);
      _undoStackCharacters -=
          evicted.insertedText.length + evicted.removedText.length;
    }
    _redoStack.clear();
  }

  void _rebuildBlocks() {
    _rebuildBlocksFromText(_buffer.text);
  }

  void _rebuildBlocksFromText(String source) {
    _blocks.clear();
    _blocks.addAll(_blocksForText(source, includeTrailingEmpty: true));
    _blocksRevision += 1;
    _blockOffsets.reset(_blocks.map((block) => block.documentLength));
  }

  TextBufferChange _replaceRangeAndRebuildBlocks(
    int start,
    int end,
    String replacement,
  ) {
    RangeError.checkValidRange(start, end, length);
    final firstBlock = blockIndexForOffset(start);
    final lastBlock = blockIndexForOffset(end);
    final regionStart = blockStart(firstBlock);
    final regionEnd = blockStart(lastBlock) + _blocks[lastBlock].documentLength;
    final change = _buffer.replace(start, end, replacement);
    final rebuiltRegionEnd = regionEnd + replacement.length - (end - start);
    final rebuiltText = _buffer.substring(regionStart, rebuiltRegionEnd);
    final replacementBlocks = _blocksForText(
      rebuiltText,
      includeTrailingEmpty: rebuiltRegionEnd == length,
    );
    _blocks.replaceRange(firstBlock, lastBlock + 1, replacementBlocks);
    if (_blocks.isEmpty) {
      _blocks.add(const LargeTextBlock(text: '', hasLineBreak: false));
    }
    _blocksRevision += 1;
    _blockOffsets.reset(_blocks.map((block) => block.documentLength));
    return change;
  }

  List<LargeTextBlock> _blocksForText(
    String source, {
    required bool includeTrailingEmpty,
  }) {
    final blocks = <LargeTextBlock>[];
    final paragraphs = source.split('\n');
    final paragraphCount = !includeTrailingEmpty && source.endsWith('\n')
        ? paragraphs.length - 1
        : paragraphs.length;
    for (var index = 0; index < paragraphCount; index += 1) {
      final paragraph = paragraphs[index];
      final hasLineBreak = index < paragraphs.length - 1;
      if (paragraph.isEmpty) {
        blocks.add(LargeTextBlock(text: '', hasLineBreak: hasLineBreak));
        continue;
      }
      var start = 0;
      while (start < paragraph.length) {
        var end = (start + ChunkedTextBuffer.targetChunkLength).clamp(
          start,
          paragraph.length,
        );
        if (end < paragraph.length && _splitsSurrogatePair(paragraph, end)) {
          end -= 1;
        }
        blocks.add(
          LargeTextBlock(
            text: paragraph.substring(start, end),
            hasLineBreak: hasLineBreak && end == paragraph.length,
          ),
        );
        start = end;
      }
    }
    return blocks;
  }

  bool _splitsSurrogatePair(String text, int offset) {
    final before = text.codeUnitAt(offset - 1);
    final after = text.codeUnitAt(offset);
    return before >= 0xD800 &&
        before <= 0xDBFF &&
        after >= 0xDC00 &&
        after <= 0xDFFF;
  }

  TextSelection _clampSelection(TextSelection selection) {
    return TextSelection(
      baseOffset: selection.baseOffset.clamp(0, length),
      extentOffset: selection.extentOffset.clamp(0, length),
      affinity: selection.affinity,
      isDirectional: selection.isDirectional,
    );
  }
}

final class _BlockOffsetIndex {
  List<int> _tree = const [];

  void reset(Iterable<int> lengths) {
    final values = lengths.toList();
    _tree = List<int>.filled(values.length + 1, 0);
    for (var index = 0; index < values.length; index += 1) {
      update(index, values[index]);
    }
  }

  void update(int index, int delta) {
    var cursor = index + 1;
    while (cursor < _tree.length) {
      _tree[cursor] += delta;
      cursor += cursor & -cursor;
    }
  }

  int prefixLength(int blockCount) {
    var result = 0;
    var cursor = blockCount;
    while (cursor > 0) {
      result += _tree[cursor];
      cursor -= cursor & -cursor;
    }
    return result;
  }

  int indexForOffset(int offset, int blockCount) {
    if (blockCount <= 1) {
      return 0;
    }
    var index = 0;
    var accumulated = 0;
    var step = 1;
    while (step << 1 < _tree.length) {
      step <<= 1;
    }
    while (step > 0) {
      final next = index + step;
      if (next < _tree.length && accumulated + _tree[next] <= offset) {
        index = next;
        accumulated += _tree[next];
      }
      step >>= 1;
    }
    return index.clamp(0, blockCount - 1);
  }
}

final class _EditRecord {
  const _EditRecord({
    required this.start,
    required this.removedText,
    required this.insertedText,
    required this.beforeSelection,
    required this.afterSelection,
    required this.recordedAt,
  });

  final int start;
  final String removedText;
  final String insertedText;
  final TextSelection beforeSelection;
  final TextSelection afterSelection;
  final DateTime recordedAt;
}
