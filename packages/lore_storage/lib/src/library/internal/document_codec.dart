import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:path/path.dart' as p;

/// 文档（章节）文件的读写编解码：BOM、CRLF、哈希修订号。
///
/// 方法按原 [LocalDirectoryLibraryRepository] 中的实现逐字搬迁。
final class DocumentCodec {
  const DocumentCodec();

  void validateDocumentFormat(String filePath, DocumentFormat format) {
    final expected = switch (format) {
      DocumentFormat.text => '.txt',
      DocumentFormat.markdown => '.md',
    };
    if (p.extension(filePath).toLowerCase() != expected) {
      throw const LibraryOperationException(
        LibraryFailure(
          code: LibraryFailureCode.unsupportedFormat,
          message: '当前文件格式不支持文本编辑。',
        ),
      );
    }
  }

  Future<DocumentSnapshot> readSnapshot(
    String filePath,
    DocumentRef ref,
  ) async {
    final bytes = await File(filePath).readAsBytes();
    final hasBom =
        bytes.length >= 3 &&
        bytes[0] == 0xef &&
        bytes[1] == 0xbb &&
        bytes[2] == 0xbf;
    final text = utf8.decode(hasBom ? bytes.sublist(3) : bytes);
    final lineEnding = lineEndingOf(text);
    return DocumentSnapshot(
      ref: ref,
      text: lineEnding == LineEnding.crlf
          ? text.replaceAll('\r\n', '\n')
          : text,
      encoding: hasBom ? TextEncoding.utf8Bom : TextEncoding.utf8,
      lineEnding: lineEnding,
      revision: revision(bytes),
    );
  }

  List<int> encodeDocument(DocumentSnapshot original, String text) {
    final normalized = switch (original.lineEnding) {
      LineEnding.crlf =>
        text
            .replaceAll('\r\n', '\n')
            .replaceAll('\r', '\n')
            .replaceAll('\n', '\r\n'),
      LineEnding.lf => text.replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
      LineEnding.mixed => text,
    };
    return [
      if (original.encoding == TextEncoding.utf8Bom) ...const [
        0xef,
        0xbb,
        0xbf,
      ],
      ...utf8.encode(normalized),
    ];
  }

  DocumentSnapshot savedSnapshot({
    required DocumentSnapshot original,
    required String text,
    required List<int> bytes,
  }) {
    return DocumentSnapshot(
      ref: original.ref,
      text: text,
      encoding: original.encoding,
      lineEnding: original.lineEnding,
      revision: revision(bytes),
    );
  }

  LineEnding lineEndingOf(String text) {
    final withoutCrLf = text.replaceAll('\r\n', '');
    final hasCrLf = text.contains('\r\n');
    final hasOtherBreak =
        withoutCrLf.contains('\n') || withoutCrLf.contains('\r');
    if (hasCrLf && !hasOtherBreak) {
      return LineEnding.crlf;
    }
    if (!hasCrLf && !withoutCrLf.contains('\r')) {
      return LineEnding.lf;
    }
    return LineEnding.mixed;
  }

  DocumentRevision revision(List<int> bytes) {
    return DocumentRevision(sha256.convert(bytes).toString());
  }
}
