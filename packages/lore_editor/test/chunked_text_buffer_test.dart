import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lore_editor/src/large_text/chunked_text_buffer.dart';

void main() {
  test('replaces ranges without rebuilding unrelated chunks', () {
    final original = List.filled(30000, '长').join();
    final buffer = ChunkedTextBuffer(original);

    final change = buffer.replace(15000, 15003, '小说');

    expect(change.removedText, '长长长');
    expect(
      buffer.text,
      '${original.substring(0, 15000)}小说${original.substring(15003)}',
    );
    expect(buffer.characterCount, 29999);
  });

  test('tracks lines and unicode character counts', () {
    final buffer = ChunkedTextBuffer('第一行\n\nA 😀');

    expect(buffer.lineBreakCount, 2);
    expect(buffer.characterCount, 5);
    expect(buffer.lineStart(6), 5);
    expect(buffer.lineEnd(0), 3);
  });

  test('matches a String reference under random edits', () {
    final random = Random(42);
    var reference = '序章\n故事开始。';
    final buffer = ChunkedTextBuffer(reference);
    const inserts = ['', '人', '\n', '😀', 'abc'];

    for (var index = 0; index < 500; index += 1) {
      final start = random.nextInt(reference.length + 1);
      final end = start + random.nextInt(reference.length - start + 1);
      final replacement = inserts[random.nextInt(inserts.length)];
      buffer.replace(start, end, replacement);
      reference =
          reference.substring(0, start) +
          replacement +
          reference.substring(end);

      expect(buffer.text, reference, reason: 'edit $index');
    }
  });
}
