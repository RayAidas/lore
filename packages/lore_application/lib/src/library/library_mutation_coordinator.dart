import 'package:lore_domain/lore_domain.dart';

/// Serializes authoritative mutations for each library.
final class LibraryMutationCoordinator {
  final Map<LibraryId, Future<void>> _tails = {};

  Future<T> run<T>(LibraryId libraryId, Future<T> Function() operation) {
    final previous = _tails[libraryId] ?? Future<void>.value();
    late final Future<T> current;
    current = previous.catchError((Object _) {}).then((_) => operation());
    final tail = current.then<void>((_) {}, onError: (_, _) {});
    _tails[libraryId] = tail;
    return current.whenComplete(() {
      if (identical(_tails[libraryId], tail)) {
        _tails.remove(libraryId);
      }
    });
  }
}
