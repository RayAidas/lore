import 'dart:async';

import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:test/test.dart';

void main() {
  test('serializes mutations for the same library after failures', () async {
    final coordinator = LibraryMutationCoordinator();
    const libraryId = LibraryId('library');
    final firstMayFinish = Completer<void>();
    final order = <String>[];

    final first = coordinator.run<void>(libraryId, () async {
      order.add('first-start');
      await firstMayFinish.future;
      order.add('first-end');
      throw StateError('failed');
    });
    final second = coordinator.run<void>(libraryId, () async {
      order.add('second');
    });

    await Future<void>.delayed(Duration.zero);
    expect(order, ['first-start']);
    firstMayFinish.complete();
    await expectLater(first, throwsStateError);
    await second;
    expect(order, ['first-start', 'first-end', 'second']);
  });
}
