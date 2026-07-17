import 'package:flutter_test/flutter_test.dart';
import 'package:lore_editor/lore_editor.dart';

void main() {
  test('tracks edits and saved versions for a long Chinese document', () {
    final text = List.filled(500000, '长').join();
    final controller = LoreTextController(text: text);
    addTearDown(controller.dispose);

    expect(controller.text.length, 500000);
    expect(controller.hasUnsavedChanges, isFalse);

    controller.text = '${controller.text}夜';

    expect(controller.editVersion, 1);
    expect(controller.hasUnsavedChanges, isTrue);
    final snapshot = controller.buildSnapshot();
    controller.markSaved(snapshot.version);
    expect(controller.hasUnsavedChanges, isFalse);

    controller.replaceFromDisk('磁盘版本');
    expect(controller.text, '磁盘版本');
    expect(controller.hasUnsavedChanges, isFalse);
  });
}
