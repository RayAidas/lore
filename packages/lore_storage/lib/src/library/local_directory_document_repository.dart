import 'dart:io';
import 'dart:typed_data';

import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:path/path.dart' as p;

import 'internal/document_codec.dart';
import 'internal/library_path_resolver.dart';
import 'internal/library_paths.dart';
import 'internal/library_storage_io.dart';

/// [DocumentRepository] 端口适配器：读取、保存、监听文档文件。
final class LocalDirectoryDocumentRepository implements DocumentRepository {
  LocalDirectoryDocumentRepository({
    required this.idGenerator,
    required this.gateway,
    required this.paths,
    required this.resolver,
    required this.io,
    required this.codec,
  });

  final IdGenerator idGenerator;
  final LibraryFileOperationsGateway? gateway;
  final LibraryPaths paths;
  final LibraryPathResolver resolver;
  final LibraryStorageIo io;
  final DocumentCodec codec;

  @override
  Future<DocumentSnapshot> readDocument(
    LibraryAccess access,
    DocumentRef ref,
  ) async {
    try {
      final rootPath = await resolver.resolveRoot(access);
      final filePath = await resolver.resolveExistingFile(
        rootPath,
        ref.relativePath,
      );
      codec.validateDocumentFormat(filePath, ref.format);
      return codec.readSnapshot(filePath, ref);
    } on LibraryOperationException {
      rethrow;
    } on FormatException {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.unsupportedEncoding,
          message: '文件不是有效的 UTF-8 文本。',
        ),
      );
    } on FileSystemException catch (error) {
      throw LibraryOperationException(io.fileSystemFailure(error));
    }
  }

  @override
  Future<DocumentSaveResult> saveDocument(
    LibraryAccess access, {
    required DocumentSnapshot original,
    required String text,
  }) async {
    String? temporaryPath;
    try {
      final rootPath = await resolver.resolveRoot(access);
      final filePath = await resolver.resolveExistingFile(
        rootPath,
        original.ref.relativePath,
      );
      codec.validateDocumentFormat(filePath, original.ref.format);
      final current = await codec.readSnapshot(filePath, original.ref);
      if (current.revision != original.revision) {
        return DocumentSaveConflict(current);
      }

      final bytes = codec.encodeDocument(original, text);
      final activeGateway = gateway;
      if (activeGateway != null) {
        final replaced = await activeGateway.replaceDocument(
          access,
          relativePath: original.ref.relativePath,
          expectedRevision: original.revision.value,
          bytes: Uint8List.fromList(bytes),
        );
        if (!replaced) {
          return DocumentSaveConflict(
            await codec.readSnapshot(filePath, original.ref),
          );
        }
        return DocumentSaveSuccess(
          codec.savedSnapshot(original: original, text: text, bytes: bytes),
        );
      }
      temporaryPath = p.join(
        p.dirname(filePath),
        '.${p.basename(filePath)}.tmp-${idGenerator.generate()}',
      );
      final temporaryFile = File(temporaryPath);
      await temporaryFile.writeAsBytes(bytes, flush: true);

      final latest = await codec.readSnapshot(filePath, original.ref);
      if (latest.revision != original.revision) {
        return DocumentSaveConflict(latest);
      }
      await temporaryFile.rename(filePath);
      temporaryPath = null;
      return DocumentSaveSuccess(
        codec.savedSnapshot(original: original, text: text, bytes: bytes),
      );
    } on LibraryOperationException {
      rethrow;
    } on FormatException {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.unsupportedEncoding,
          message: '文件不是有效的 UTF-8 文本。',
        ),
      );
    } on FileSystemException catch (error) {
      throw LibraryOperationException(io.fileSystemFailure(error));
    } finally {
      if (temporaryPath != null) {
        await io.deleteFileSafely(temporaryPath);
      }
    }
  }

  @override
  Stream<DocumentChange> watchDocuments(LibraryAccess access) async* {
    final rootPath = await resolver.resolveRoot(access);
    await for (final event in Directory(rootPath).watch(recursive: true)) {
      final relativePath = p.relative(event.path, from: rootPath);
      if (paths.isHiddenPath(relativePath)) {
        continue;
      }
      final type = switch (event) {
        FileSystemCreateEvent() => DocumentChangeType.created,
        FileSystemDeleteEvent() => DocumentChangeType.deleted,
        FileSystemMoveEvent() => DocumentChangeType.moved,
        _ => DocumentChangeType.modified,
      };
      yield DocumentChange(relativePath: relativePath, type: type);
      if (event case FileSystemMoveEvent(
        :final destination?,
      ) when p.isWithin(rootPath, destination)) {
        yield DocumentChange(
          relativePath: p.relative(destination, from: rootPath),
          type: DocumentChangeType.created,
        );
      }
    }
  }
}
