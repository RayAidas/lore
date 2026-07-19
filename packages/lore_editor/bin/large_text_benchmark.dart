import 'dart:io';

import 'package:flutter/services.dart';
import 'package:lore_editor/lore_editor.dart';

void main() {
  final paragraph = List.filled(99, '长').join();
  final text = List.generate(10000, (_) => '$paragraph\n').join();
  final openStopwatch = Stopwatch()..start();
  final controller = LoreLargeTextController(text: text);
  openStopwatch.stop();

  final editStopwatch = Stopwatch()..start();
  for (var index = 0; index < 1000; index += 1) {
    controller.replaceBlockRange(
      0,
      index,
      index,
      '新',
      TextSelection.collapsed(offset: index + 1),
    );
  }
  editStopwatch.stop();

  stdout.writeln('document=${controller.length} utf16 units');
  stdout.writeln('blocks=${controller.blocks.length}');
  stdout.writeln('open=${openStopwatch.elapsedMilliseconds}ms');
  stdout.writeln('edits=${editStopwatch.elapsedMilliseconds}ms');
  controller.dispose();
}
