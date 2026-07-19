part of '../storage_backed_library_repository.dart';

mixin _StorageBackedDocumentRepository on _StorageBackedLibrarySupport
    implements DocumentRepository {
  @override
  Future<DocumentSnapshot> readDocument(
    LibraryAccess access,
    DocumentRef ref,
  ) async {
    _validateDocumentRef(ref);
    final storage = await storageFactory.open(access);
    final path = _publicPath(ref.relativePath);
    for (var attempt = 0; attempt < 2; attempt += 1) {
      final before = await storage.stat(path);
      if (before?.type != StorageEntryType.file || before?.revision == null) {
        throw _notFound();
      }
      final bytes = await storage.readBytes(path);
      final after = await storage.stat(path);
      if (after?.revision != before!.revision) continue;
      ({String text, bool hasBom, LineEnding lineEnding}) decoded;
      try {
        decoded = await Isolate.run(() => _decodeDocument(bytes));
      } on FormatException {
        throw const LibraryOperationException(
          LibraryFailure(
            code: LibraryFailureCode.unsupportedEncoding,
            message: '文件不是有效的 UTF-8 文本。',
          ),
        );
      }
      return DocumentSnapshot(
        ref: ref,
        text: decoded.text,
        encoding: decoded.hasBom ? TextEncoding.utf8Bom : TextEncoding.utf8,
        lineEnding: decoded.lineEnding,
        revision: DocumentRevision(after!.revision!),
      );
    }
    throw const LibraryOperationException(
      LibraryFailure(
        code: LibraryFailureCode.externalModification,
        message: '文档读取期间持续发生外部修改，请重试。',
      ),
    );
  }

  @override
  Future<DocumentSaveResult> saveDocument(
    LibraryAccess access, {
    required DocumentSnapshot original,
    required String text,
  }) async {
    final storage = await storageFactory.open(access);
    final bytes = await Isolate.run(
      () => _encodeDocument(text, original.lineEnding, original.encoding),
    );
    final result = await storage.replaceFile(
      _publicPath(original.ref.relativePath),
      expectedRevision: original.revision.value,
      bytes: bytes,
    );
    if (result case StorageReplaceConflict()) {
      return DocumentSaveConflict(await readDocument(access, original.ref));
    }
    return DocumentSaveSuccess(
      DocumentSnapshot(
        ref: original.ref,
        text: text,
        encoding: original.encoding,
        lineEnding: original.lineEnding,
        revision: DocumentRevision((result as StorageReplaceSuccess).revision),
      ),
    );
  }

  @override
  Stream<DocumentChange> watchDocuments(LibraryAccess access) async* {
    final storage = await storageFactory.open(access);
    await for (final change in storage.watch()) {
      if (_isHiddenPath(change.path)) continue;
      yield DocumentChange(
        relativePath: change.path.value,
        type: switch (change.type) {
          StorageChangeType.created => DocumentChangeType.created,
          StorageChangeType.modified => DocumentChangeType.modified,
          StorageChangeType.deleted => DocumentChangeType.deleted,
          StorageChangeType.moved => DocumentChangeType.moved,
        },
      );
      final destination = change.destination;
      if (change.type == StorageChangeType.moved &&
          destination != null &&
          !_isHiddenPath(destination)) {
        yield DocumentChange(
          relativePath: destination.value,
          type: DocumentChangeType.created,
        );
      }
    }
  }
}

({String text, bool hasBom, LineEnding lineEnding}) _decodeDocument(
  Uint8List bytes,
) {
  final hasBom =
      bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF;
  final content = hasBom ? bytes.sublist(3) : bytes;
  final rawText = utf8.decode(content);
  final crlf = RegExp(r'\r\n').allMatches(rawText).length;
  final lf = RegExp(r'(?<!\r)\n').allMatches(rawText).length;
  final lineEnding = crlf > 0 && lf > 0
      ? LineEnding.mixed
      : crlf > 0
      ? LineEnding.crlf
      : LineEnding.lf;
  return (
    text: rawText.replaceAll('\r\n', '\n'),
    hasBom: hasBom,
    lineEnding: lineEnding,
  );
}

Uint8List _encodeDocument(
  String text,
  LineEnding lineEnding,
  TextEncoding encoding,
) {
  final normalized = lineEnding == LineEnding.crlf
      ? text.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n')
      : text;
  final encoded = utf8.encode(normalized);
  return Uint8List.fromList(
    encoding == TextEncoding.utf8Bom ? [0xEF, 0xBB, 0xBF, ...encoded] : encoded,
  );
}
