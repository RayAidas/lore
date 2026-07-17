enum DocumentFormat { text, markdown }

enum TextEncoding { utf8, utf8Bom }

enum LineEnding { lf, crlf, mixed }

final class DocumentRef {
  const DocumentRef({required this.relativePath, required this.format});

  final String relativePath;
  final DocumentFormat format;

  DocumentRef copyWith({String? relativePath, DocumentFormat? format}) {
    return DocumentRef(
      relativePath: relativePath ?? this.relativePath,
      format: format ?? this.format,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is DocumentRef &&
        other.relativePath == relativePath &&
        other.format == format;
  }

  @override
  int get hashCode => Object.hash(relativePath, format);
}

final class DocumentRevision {
  const DocumentRevision(this.value);

  final String value;

  @override
  bool operator ==(Object other) {
    return other is DocumentRevision && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;
}

final class DocumentSnapshot {
  const DocumentSnapshot({
    required this.ref,
    required this.text,
    required this.encoding,
    required this.lineEnding,
    required this.revision,
  });

  final DocumentRef ref;
  final String text;
  final TextEncoding encoding;
  final LineEnding lineEnding;
  final DocumentRevision revision;
}
