enum LibraryBackendKind { localDirectory, androidSaf }

final class LibraryAccess {
  const LibraryAccess({
    this.backend = LibraryBackendKind.localDirectory,
    required this.token,
    required this.displayPath,
    required this.isPending,
  });

  final LibraryBackendKind backend;
  final String token;
  final String displayPath;
  final bool isPending;

  LibraryAccess copyWith({
    LibraryBackendKind? backend,
    String? token,
    String? displayPath,
    bool? isPending,
  }) {
    return LibraryAccess(
      backend: backend ?? this.backend,
      token: token ?? this.token,
      displayPath: displayPath ?? this.displayPath,
      isPending: isPending ?? this.isPending,
    );
  }
}
