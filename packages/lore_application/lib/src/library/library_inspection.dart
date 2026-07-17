import 'package:lore_domain/lore_domain.dart';

import 'library_failure.dart';

sealed class LibraryInspection {
  const LibraryInspection();
}

final class LibraryInspectionReady extends LibraryInspection {
  const LibraryInspectionReady(this.metadata);

  final LibraryMetadata metadata;
}

final class LibraryInspectionNeedsInitialization extends LibraryInspection {
  const LibraryInspectionNeedsInitialization();
}

final class LibraryInspectionFailure extends LibraryInspection {
  const LibraryInspectionFailure(this.failure);

  final LibraryFailure failure;
}
