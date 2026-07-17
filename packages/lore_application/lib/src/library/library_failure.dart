enum LibraryFailureCode {
  permissionDenied,
  notFound,
  notWritable,
  metadataCorrupt,
  unsupportedSchema,
  invalidLocation,
  platformUnsupported,
  io,
}

final class LibraryFailure {
  const LibraryFailure({required this.code, required this.message});

  final LibraryFailureCode code;
  final String message;
}

final class LibraryOperationException implements Exception {
  const LibraryOperationException(this.failure);

  final LibraryFailure failure;

  @override
  String toString() => failure.message;
}
