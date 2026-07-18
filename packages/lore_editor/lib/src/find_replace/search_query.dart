/// 一次匹配的字符区间（半开区间 [start, end)）。
final class FindMatch {
  const FindMatch({required this.start, required this.end});

  final int start;
  final int end;

  int get length => end - start;
}

/// 不可变的查找条件。纯 Dart，无 Flutter 依赖，便于单测。
final class SearchQuery {
  const SearchQuery({
    required this.pattern,
    required this.caseSensitive,
    required this.useRegex,
  });

  final String pattern;
  final bool caseSensitive;
  final bool useRegex;

  /// 在 [text] 中找出所有匹配。空模式返回空列表；非法正则返回空列表。
  List<FindMatch> findAllIn(String text) {
    if (pattern.isEmpty) {
      return const [];
    }
    if (useRegex) {
      try {
        final regex = RegExp(
          pattern,
          caseSensitive: caseSensitive,
          multiLine: true,
        );
        return regex
            .allMatches(text)
            .map((match) => FindMatch(start: match.start, end: match.end))
            .toList(growable: false);
      } on FormatException {
        return const [];
      }
    }
    final needle = caseSensitive ? pattern : pattern.toLowerCase();
    final hay = caseSensitive ? text : text.toLowerCase();
    final result = <FindMatch>[];
    var from = 0;
    while (true) {
      final index = hay.indexOf(needle, from);
      if (index == -1) {
        break;
      }
      result.add(FindMatch(start: index, end: index + needle.length));
      from = index + needle.length;
    }
    return result;
  }
}
