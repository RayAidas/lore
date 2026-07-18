/// A portable path relative to a library root.
///
/// Serialized paths always use `/`, regardless of the host platform. The
/// empty value is reserved for [root].
final class LogicalPath {
  const LogicalPath._(this.value);

  factory LogicalPath.parse(String value) {
    if (value.isEmpty) {
      return root;
    }
    if (value.startsWith('/') ||
        value.contains(r'\') ||
        value.contains('\u0000')) {
      throw FormatException('Path must be a portable relative path.', value);
    }
    final segments = value.split('/');
    if (segments.any(
      (segment) => segment.isEmpty || segment == '.' || segment == '..',
    )) {
      throw FormatException('Path contains an invalid segment.', value);
    }
    return LogicalPath._(value);
  }

  static const root = LogicalPath._('');

  final String value;

  bool get isRoot => value.isEmpty;

  String get name => isRoot ? '' : value.split('/').last;

  LogicalPath? get parent {
    if (isRoot) {
      return null;
    }
    final separator = value.lastIndexOf('/');
    return separator < 0 ? root : LogicalPath._(value.substring(0, separator));
  }

  LogicalPath child(String name) {
    final child = LogicalPath.parse(name);
    if (child.isRoot || child.value.contains('/')) {
      throw FormatException('Child name must contain one segment.', name);
    }
    return LogicalPath._(isRoot ? child.value : '$value/${child.value}');
  }

  bool contains(LogicalPath other) {
    return !other.isRoot && (isRoot || other.value.startsWith('$value/'));
  }

  @override
  bool operator ==(Object other) =>
      other is LogicalPath && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
