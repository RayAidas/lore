import 'package:flutter/foundation.dart';

import 'search_query.dart';

/// 一次替换操作的结果。调用方负责把 [text] 写回编辑器 controller，
/// 并把光标定位到 [cursor]（仅单次替换提供）。
final class FindReplaceResult {
  const FindReplaceResult({
    required this.text,
    required this.replaced,
    this.cursor,
  });

  final String text;
  final bool replaced;
  final int? cursor;
}

/// 查找替换的可观察状态。
///
/// 设计为与具体编辑器 controller 解耦：UI 层在文本变化时调用 [recompute]
/// 刷新匹配，跳转通过读取 [currentMatch] 后自行设置编辑器选区，
/// 替换则取回新文本自行写回——这样写回会触发编辑器的脏标记与自动保存。
final class FindReplaceController extends ChangeNotifier {
  FindReplaceController();

  String _pattern = '';
  String _replacement = '';
  bool _caseSensitive = false;
  bool _useRegex = false;

  List<FindMatch> _matches = const [];
  int _currentIndex = -1;
  String _lastText = '';

  String get pattern => _pattern;
  String get replacement => _replacement;
  bool get caseSensitive => _caseSensitive;
  bool get useRegex => _useRegex;
  List<FindMatch> get matches => List.unmodifiable(_matches);
  int get currentIndex => _currentIndex;
  int get matchCount => _matches.length;

  FindMatch? get currentMatch =>
      (_currentIndex >= 0 && _currentIndex < _matches.length)
      ? _matches[_currentIndex]
      : null;

  SearchQuery get _searchQuery => SearchQuery(
    pattern: _pattern,
    caseSensitive: _caseSensitive,
    useRegex: _useRegex,
  );

  void setPattern(String value) {
    _pattern = value;
    recompute(_lastText);
  }

  void setReplacement(String value) {
    _replacement = value;
    notifyListeners();
  }

  void setCaseSensitive(bool value) {
    _caseSensitive = value;
    recompute(_lastText);
  }

  void setUseRegex(bool value) {
    _useRegex = value;
    recompute(_lastText);
  }

  /// 用当前查询条件在 [text] 上重算匹配，并保持游标在合法范围内。
  void recompute(String text) {
    _lastText = text;
    _matches = _searchQuery.findAllIn(text);
    if (_matches.isEmpty) {
      _currentIndex = -1;
    } else if (_currentIndex < 0 || _currentIndex >= _matches.length) {
      _currentIndex = 0;
    }
    notifyListeners();
  }

  void next() {
    if (_matches.isEmpty) {
      return;
    }
    _currentIndex = (_currentIndex + 1) % _matches.length;
    notifyListeners();
  }

  void previous() {
    if (_matches.isEmpty) {
      return;
    }
    _currentIndex = (_currentIndex - 1) % _matches.length;
    notifyListeners();
  }

  /// 替换当前匹配，返回新文本与建议光标位置。
  FindReplaceResult applyReplaceCurrent(String text) {
    final match = currentMatch;
    if (match == null) {
      return FindReplaceResult(text: text, replaced: false);
    }
    if (_useRegex) {
      // 正则模式用 replaceFirstMapped 从当前匹配起点替换，保证捕获组
      // 由 RegExp 自身解析（避免 matchAsPrefix 在 anchored/lookbehind 时
      // 失败而静默退化为原文）。
      try {
        final regex = RegExp(
          _pattern,
          caseSensitive: _caseSensitive,
          multiLine: true,
        );
        final replaced = text.replaceFirstMapped(
          regex,
          (regexMatch) => _expandReplacement(_replacement, regexMatch),
          match.start,
        );
        return FindReplaceResult(text: replaced, replaced: true);
      } on FormatException {
        return FindReplaceResult(text: text, replaced: false);
      }
    }
    final newText =
        text.substring(0, match.start) +
        _replacement +
        text.substring(match.end);
    return FindReplaceResult(
      text: newText,
      replaced: true,
      cursor: match.start + _replacement.length,
    );
  }

  /// 替换全部匹配，返回新文本。普通模式正向遍历拼接避免偏移错乱；
  /// 正则模式一次性交给 RegExp.replaceAllMapped，性能与捕获组都更好。
  String applyReplaceAll(String text) {
    if (_matches.isEmpty) {
      return text;
    }
    if (_useRegex) {
      try {
        final regex = RegExp(
          _pattern,
          caseSensitive: _caseSensitive,
          multiLine: true,
        );
        return text.replaceAllMapped(
          regex,
          (regexMatch) => _expandReplacement(_replacement, regexMatch),
        );
      } on FormatException {
        return text;
      }
    }
    final buffer = StringBuffer();
    var cursor = 0;
    for (final match in _matches) {
      buffer.write(text.substring(cursor, match.start));
      buffer.write(_replacement);
      cursor = match.end;
    }
    buffer.write(text.substring(cursor));
    return buffer.toString();
  }

  String _expandReplacement(String template, Match match) {
    final buffer = StringBuffer();
    var i = 0;
    while (i < template.length) {
      final char = template[i];
      if (char == r'$' && i + 1 < template.length) {
        final digit = int.tryParse(template[i + 1]);
        if (digit != null && digit >= 0 && digit <= 9) {
          buffer.write(match.group(digit) ?? '');
          i += 2;
          continue;
        }
      }
      buffer.write(char);
      i += 1;
    }
    return buffer.toString();
  }
}
