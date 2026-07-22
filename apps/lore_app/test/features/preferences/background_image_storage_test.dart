import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lore_app/features/preferences/background_image_storage.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temporaryDirectory;
  late Directory supportDirectory;
  late BackgroundImageStorage storage;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'lore-background-storage-test-',
    );
    supportDirectory = Directory(p.join(temporaryDirectory.path, 'support'));
    storage = BackgroundImageStorage(
      supportDirectory: () async {
        return supportDirectory;
      },
    );
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'imports a private copy under the application support directory',
    () async {
      final source = File(p.join(temporaryDirectory.path, 'source.jpg'));
      await source.writeAsBytes([1, 2, 3, 4]);

      final importedPath = await storage.importImage(source.path);

      expect(p.isWithin(supportDirectory.path, importedPath), isTrue);
      expect(p.basename(p.dirname(importedPath)), 'backgrounds');
      expect(await File(importedPath).readAsBytes(), [1, 2, 3, 4]);
    },
  );

  test('deletes only images owned by the application', () async {
    final managed = File(
      p.join(supportDirectory.path, 'backgrounds', 'managed.jpg'),
    );
    final external = File(p.join(temporaryDirectory.path, 'external.jpg'));
    await managed.parent.create(recursive: true);
    await managed.writeAsBytes([1]);
    await external.writeAsBytes([2]);

    await storage.deleteManagedImage(external.path);
    await storage.deleteManagedImage(managed.path);

    expect(await external.exists(), isTrue);
    expect(await managed.exists(), isFalse);
  });
}
