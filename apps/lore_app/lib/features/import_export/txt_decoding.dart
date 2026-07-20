import 'dart:convert';
import 'dart:typed_data';

import 'package:charset_converter/charset_converter.dart';
import 'package:lore_application/lore_application.dart';

/// 把 TXT 文件字节解码为字符串，兼容中文小说常见的多种编码：
///
/// - UTF-8 BOM（`EF BB BF`）：剥除后按 UTF-8 解码。
/// - UTF-16 BOM（`FF FE` / `FE FF`）：抛 `unsupportedFormat`，明确提示用户
///   转码——避免落到 GB18030 后被静默解码成乱码（看起来成功、实则数据损坏）。
/// - 其余：先用容错 UTF-8（`allowMalformed`）解码，按替换符 `U+FFFD` 占比判断
///   是否「基本是 UTF-8」。占比 < 1% 视为 UTF-8（仅少量坏字节，保留解码）；
///   否则视为非 UTF-8，按 **GB18030** 解码（GBK/GB2312 子集）。这样既不会
///   因单个坏字节让整篇 UTF-8 误退回 GB18030 全篇乱码，也能正确还原 GBK 源。
///
/// 因 [CharsetConverter.decode] 走平台通道，本函数为异步。
Future<String> decodeTxtBytes(Uint8List bytes) async {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3));
  }
  if (bytes.length >= 2 &&
      ((bytes[0] == 0xFF && bytes[1] == 0xFE) ||
          (bytes[0] == 0xFE && bytes[1] == 0xFF))) {
    throw const LibraryOperationException(
      LibraryFailure(
        code: LibraryFailureCode.unsupportedFormat,
        message: 'UTF-16 编码暂不支持，请先将文件另存为 UTF-8 或 GBK 后再导入。',
      ),
    );
  }
  final decoded = utf8.decode(bytes, allowMalformed: true);
  if (_looksLikeValidUtf8(decoded)) {
    return decoded;
  }
  return CharsetConverter.decode('gb18030', bytes);
}

/// 容错 UTF-8 解码结果是否「基本合法」：无替换符，或替换符占比 < 1%
/// （少量坏字节可接受，避免整篇误退回 GB18030）。
bool _looksLikeValidUtf8(String decoded) {
  if (decoded.isEmpty) {
    return true;
  }
  var replacements = 0;
  for (var i = 0; i < decoded.length; i++) {
    if (decoded.codeUnitAt(i) == 0xFFFD) {
      replacements += 1;
    }
  }
  return replacements / decoded.length < 0.01;
}
