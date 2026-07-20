import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lore_app/features/import_export/txt_decoding.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // GB18030 解码由原生 charset_converter 插件承担；单测里 mock 其通道，
  // 校验「非 UTF-8 → 回退 GB18030」的路由与结果传递。
  const channel = MethodChannel('charset_converter');
  String? mockedDecode;
  setUp(() {
    mockedDecode = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'decode') {
            return mockedDecode;
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('decodeTxtBytes', () {
    test('decodes plain UTF-8 without BOM (no native call)', () async {
      final bytes = Uint8List.fromList(utf8.encode('第1章 起点\n起点正文。'));
      expect(await decodeTxtBytes(bytes), '第1章 起点\n起点正文。');
    });

    test('strips UTF-8 BOM and decodes the body', () async {
      final body = utf8.encode('第1章 起点');
      final withBom = <int>[0xEF, 0xBB, 0xBF, ...body];
      expect(await decodeTxtBytes(Uint8List.fromList(withBom)), '第1章 起点');
    });

    test('falls back to GB18030 for non-UTF-8 bytes (regression)', () async {
      // 非 UTF-8 的高位字节序列（GBK 编码的典型形态）。
      final gbkLikeBytes = Uint8List.fromList([0xB5, 0xDA, 0xD5, 0xC2]);
      expect(() => utf8.decode(gbkLikeBytes), throwsA(isA<FormatException>()));
      mockedDecode = '第章';
      expect(await decodeTxtBytes(gbkLikeBytes), '第章');
    });

    test('treats ASCII as UTF-8', () async {
      final bytes = Uint8List.fromList(ascii.encode('Chapter 1 Begins'));
      expect(await decodeTxtBytes(bytes), 'Chapter 1 Begins');
    });
  });
}
