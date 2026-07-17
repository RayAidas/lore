import 'package:lore_domain/lore_domain.dart';

import '../ports/document_repository.dart';
import '../ports/library_tree_repository.dart';
import '../ports/workspace_session_repository.dart';
import 'library_bootstrap.dart';
import 'workspace_session.dart';

final class LibraryWorkspaceService {
  const LibraryWorkspaceService({
    required this.treeRepository,
    required this.documentRepository,
    required this.sessionRepository,
  });

  final LibraryTreeRepository treeRepository;
  final DocumentRepository documentRepository;
  final WorkspaceSessionRepository sessionRepository;

  Future<List<LibraryEntry>> listChildren(
    LibrarySession session, {
    String relativePath = '',
  }) {
    return treeRepository.listChildren(
      session.access,
      relativePath: relativePath,
    );
  }

  Future<LibraryEntry> createDirectory(
    LibrarySession session, {
    required String parentPath,
    required String name,
  }) {
    return treeRepository.createDirectory(
      session.access,
      parentPath: parentPath,
      name: name,
    );
  }

  Future<LibraryEntry> createDocument(
    LibrarySession session, {
    required String parentPath,
    required String name,
    required DocumentFormat format,
    String initialText = '',
  }) {
    return treeRepository.createDocument(
      session.access,
      parentPath: parentPath,
      name: name,
      format: format,
      initialText: initialText,
    );
  }

  Future<LibraryEntry> renameEntry(
    LibrarySession session, {
    required String relativePath,
    required String newName,
  }) {
    return treeRepository.renameEntry(
      session.access,
      relativePath: relativePath,
      newName: newName,
    );
  }

  Future<DocumentSnapshot> readDocument(
    LibrarySession session,
    DocumentRef ref,
  ) {
    return documentRepository.readDocument(session.access, ref);
  }

  Future<DocumentSaveResult> saveDocument(
    LibrarySession session, {
    required DocumentSnapshot original,
    required String text,
  }) {
    return documentRepository.saveDocument(
      session.access,
      original: original,
      text: text,
    );
  }

  Stream<DocumentChange> watchDocuments(LibrarySession session) {
    return documentRepository.watchDocuments(session.access);
  }

  Future<WorkspaceSessionSnapshot?> loadSession(LibrarySession session) {
    return sessionRepository.load(session.metadata.id);
  }

  Future<void> saveSession(
    LibrarySession session,
    WorkspaceSessionSnapshot snapshot,
  ) {
    return sessionRepository.save(session.metadata.id, snapshot);
  }
}
