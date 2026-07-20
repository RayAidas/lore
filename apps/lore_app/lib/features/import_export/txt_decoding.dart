import 'dart:convert';
import 'dart:typed_data';

import 'package:charset_converter/charset_converter.dart';

/// 把 TXT 文件字节解码为字符串，按「UTF-8 BOM → 严格 UTF-8 → GB18030 回退」
/// 顺序处理，兼容中文小说常见的多种编码：
///
/// - UTF-8 BOM（`EF BB BF`）：剥除后按 UTF-8 解码。
/// - 无 BOM：先严格 UTF-8 解码（`allowMalformed: false`）；合法 UTF-8 能正确
///   还原现代 TXT，且不会被 GBK 双字节误判。
/// - 严格 UTF-8 抛 [FormatException]：按 **GB18030** 解码（GBK / GB2312 均为
///   其子集，覆盖中文小说绝大多数遗留编码）。走 [CharsetConverter] 原生
///   平台编码表，准确可靠；macOS / iOS / Android 均原生支持 `gb18030`。
///
/// 因 [CharsetConverter.decode] 走平台通道，本函数为异步。不处理 UTF-16
/// （极少见于小说 TXT）；如遇 UTF-16 BOM 会落到 GB18030 回退。
Future<String> decodeTxtBytes(Uint8List bytes) async {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3));
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return CharsetConverter.decode('gb18030', bytes);
  }
}
