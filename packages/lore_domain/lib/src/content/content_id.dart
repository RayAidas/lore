final class ContentId {
  const ContentId(this.value);

  final String value;

  @override
  bool operator ==(Object other) {
    return identical(this, other) || other is ContentId && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
