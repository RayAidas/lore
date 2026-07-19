import 'dart:math' as math;

final class TextBufferChange {
  const TextBufferChange({
    required this.start,
    required this.removedText,
    required this.insertedText,
  });

  final int start;
  final String removedText;
  final String insertedText;
}

final class ChunkedTextBuffer {
  ChunkedTextBuffer(String text) {
    if (text.isNotEmpty) {
      _root = _build(text);
    }
  }

  static const targetChunkLength = 8192;

  _TextNode? _root;
  var _prioritySeed = 0x4c6f7265;

  int get length => _root?.length ?? 0;

  int get lineBreakCount => _root?.lineBreakCount ?? 0;

  int get characterCount => _root?.characterCount ?? 0;

  /// 完整文本。每次访问都会把所有 chunk 重新拼接一遍（O(n)），适合保存、
  /// 查找等本来就需要的路径；不要在热路径（如监听回调、布局）里反复读取。
  String get text => chunks.join();

  Iterable<String> get chunks sync* {
    final stack = <_TextNode>[];
    var current = _root;
    while (current != null || stack.isNotEmpty) {
      while (current != null) {
        stack.add(current);
        current = current.left;
      }
      current = stack.removeLast();
      yield current.chunk;
      current = current.right;
    }
  }

  String substring(int start, [int? end]) {
    final resolvedEnd = end ?? length;
    RangeError.checkValidRange(start, resolvedEnd, length);
    if (start == resolvedEnd) {
      return '';
    }
    final output = StringBuffer();
    _writeRange(_root, start, resolvedEnd, 0, output);
    return output.toString();
  }

  TextBufferChange replace(int start, int end, String replacement) {
    RangeError.checkValidRange(start, end, length);
    final removedText = substring(start, end);
    final (before, tail) = _split(_root, start);
    final (_, after) = _split(tail, end - start);
    final inserted = replacement.isEmpty ? null : _build(replacement);
    _root = _merge(_merge(before, inserted), after);
    return TextBufferChange(
      start: start,
      removedText: removedText,
      insertedText: replacement,
    );
  }

  int lineStart(int offset) {
    RangeError.checkValueInInterval(offset, 0, length);
    if (offset == 0) {
      return 0;
    }
    final prefix = substring(0, offset);
    final newline = prefix.lastIndexOf('\n');
    return newline < 0 ? 0 : newline + 1;
  }

  int lineEnd(int offset) {
    RangeError.checkValueInInterval(offset, 0, length);
    final suffix = substring(offset);
    final newline = suffix.indexOf('\n');
    return newline < 0 ? length : offset + newline;
  }

  _TextNode? _build(String text) {
    _TextNode? result;
    var offset = 0;
    while (offset < text.length) {
      var end = math.min(offset + targetChunkLength, text.length);
      if (end < text.length && _splitsSurrogatePair(text, end)) {
        end -= 1;
      }
      result = _merge(result, _node(text.substring(offset, end)));
      offset = end;
    }
    return result;
  }

  (_TextNode?, _TextNode?) _split(_TextNode? node, int offset) {
    if (node == null) {
      return (null, null);
    }
    final leftLength = node.left?.length ?? 0;
    if (offset < leftLength) {
      final (before, after) = _split(node.left, offset);
      node.left = after;
      node.recalculate();
      return (before, node);
    }
    final chunkEnd = leftLength + node.chunk.length;
    if (offset > chunkEnd) {
      final (before, after) = _split(node.right, offset - chunkEnd);
      node.right = before;
      node.recalculate();
      return (node, after);
    }
    final localOffset = offset - leftLength;
    final originalLeft = node.left;
    final originalRight = node.right;
    _TextNode? before = originalLeft;
    _TextNode? after = originalRight;
    if (localOffset > 0) {
      before = _merge(before, _node(node.chunk.substring(0, localOffset)));
    }
    if (localOffset < node.chunk.length) {
      after = _merge(_node(node.chunk.substring(localOffset)), after);
    }
    return (before, after);
  }

  _TextNode? _merge(_TextNode? left, _TextNode? right) {
    if (left == null) {
      return right;
    }
    if (right == null) {
      return left;
    }
    if (left.priority >= right.priority) {
      left.right = _merge(left.right, right);
      left.recalculate();
      return left;
    }
    right.left = _merge(left, right.left);
    right.recalculate();
    return right;
  }

  _TextNode _node(String chunk) {
    _prioritySeed = (_prioritySeed * 1103515245 + 12345) & 0x7fffffff;
    return _TextNode(chunk, _prioritySeed);
  }

  void _writeRange(
    _TextNode? node,
    int start,
    int end,
    int nodeStart,
    StringBuffer output,
  ) {
    if (node == null || start >= end) {
      return;
    }
    final leftLength = node.left?.length ?? 0;
    final chunkStart = nodeStart + leftLength;
    final chunkEnd = chunkStart + node.chunk.length;
    if (start < chunkStart) {
      _writeRange(node.left, start, end, nodeStart, output);
    }
    final overlapStart = math.max(start, chunkStart);
    final overlapEnd = math.min(end, chunkEnd);
    if (overlapStart < overlapEnd) {
      output.write(
        node.chunk.substring(
          overlapStart - chunkStart,
          overlapEnd - chunkStart,
        ),
      );
    }
    if (end > chunkEnd) {
      _writeRange(node.right, start, end, chunkEnd, output);
    }
  }

  bool _splitsSurrogatePair(String text, int offset) {
    final before = text.codeUnitAt(offset - 1);
    final after = text.codeUnitAt(offset);
    return before >= 0xD800 &&
        before <= 0xDBFF &&
        after >= 0xDC00 &&
        after <= 0xDFFF;
  }
}

final class _TextNode {
  _TextNode(this.chunk, this.priority) {
    recalculate();
  }

  final String chunk;
  final int priority;
  _TextNode? left;
  _TextNode? right;
  late int length;
  late int lineBreakCount;
  late int characterCount;

  void recalculate() {
    length = (left?.length ?? 0) + chunk.length + (right?.length ?? 0);
    lineBreakCount =
        (left?.lineBreakCount ?? 0) +
        '\n'.allMatches(chunk).length +
        (right?.lineBreakCount ?? 0);
    characterCount =
        (left?.characterCount ?? 0) +
        _countCharacters(chunk) +
        (right?.characterCount ?? 0);
  }

  static int _countCharacters(String text) {
    var count = 0;
    for (final rune in text.runes) {
      if (!_isWhitespace(rune)) {
        count += 1;
      }
    }
    return count;
  }

  static bool _isWhitespace(int rune) {
    return rune == 0x09 ||
        rune == 0x0A ||
        rune == 0x0B ||
        rune == 0x0C ||
        rune == 0x0D ||
        rune == 0x20 ||
        rune == 0x85 ||
        rune == 0xA0 ||
        rune == 0x1680 ||
        (rune >= 0x2000 && rune <= 0x200A) ||
        rune == 0x2028 ||
        rune == 0x2029 ||
        rune == 0x202F ||
        rune == 0x205F ||
        rune == 0x3000 ||
        rune == 0xFEFF;
  }
}
