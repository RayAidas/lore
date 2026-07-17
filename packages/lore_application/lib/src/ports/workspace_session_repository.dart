import 'package:lore_domain/lore_domain.dart';

import '../library/workspace_session.dart';

abstract interface class WorkspaceSessionRepository {
  Future<WorkspaceSessionSnapshot?> load(LibraryId libraryId);

  Future<void> save(LibraryId libraryId, WorkspaceSessionSnapshot snapshot);
}
