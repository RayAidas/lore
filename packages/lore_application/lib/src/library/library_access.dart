final class LibraryAccess {
  const LibraryAccess({
    required this.token,
    required this.displayPath,
    required this.isPending,
  });

  final String token;
  final String displayPath;
  final bool isPending;
}
