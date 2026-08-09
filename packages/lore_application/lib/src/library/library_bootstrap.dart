import 'package:lore_domain/lore_domain.dart';

import '../ports/library_access_gateway.dart';
import '../ports/library_repository.dart';
import 'library_access.dart';
import 'library_failure.dart';
import 'library_inspection.dart';

final class LibrarySession {
  const LibrarySession({required this.access, required this.metadata});

  final LibraryAccess access;
  final LibraryMetadata metadata;
}

sealed class LibraryBootstrapResult {
  const LibraryBootstrapResult();
}

final class LibraryBootstrapSelectionRequired extends LibraryBootstrapResult {
  const LibraryBootstrapSelectionRequired();
}

final class LibraryBootstrapNeedsInitialization extends LibraryBootstrapResult {
  const LibraryBootstrapNeedsInitialization(this.access);

  final LibraryAccess access;
}

final class LibraryBootstrapReady extends LibraryBootstrapResult {
  const LibraryBootstrapReady(this.session);

  final LibrarySession session;
}

final class LibraryBootstrapFailure extends LibraryBootstrapResult {
  const LibraryBootstrapFailure(this.failure);

  final LibraryFailure failure;
}

final class LibraryBootstrapService {
  const LibraryBootstrapService({
    required this._accessGateway,
    required this._repository,
  });

  final LibraryAccessGateway _accessGateway;
  final LibraryRepository _repository;

  Future<LibraryBootstrapResult> restore() async {
    try {
      final access = await _accessGateway.restore();
      if (access == null) {
        return const LibraryBootstrapSelectionRequired();
      }
      return _inspect(access);
    } on LibraryAccessException catch (error) {
      return LibraryBootstrapFailure(error.failure);
    }
  }

  Future<LibraryBootstrapResult?> select() async {
    try {
      final access = await _accessGateway.select();
      if (access == null) {
        return null;
      }

      final result = await _inspect(access);
      if (result is LibraryBootstrapReady) {
        await _accessGateway.commit();
        return LibraryBootstrapReady(
          LibrarySession(
            access: LibraryAccess(
              token: access.token,
              displayPath: access.displayPath,
              isPending: false,
            ),
            metadata: result.session.metadata,
          ),
        );
      }
      if (result is LibraryBootstrapFailure) {
        await _discardSafely();
      }
      return result;
    } on LibraryAccessException catch (error) {
      await _discardSafely();
      return LibraryBootstrapFailure(error.failure);
    }
  }

  /// 创建名为 [name] 的新书库目录并立即初始化。
  /// 用户取消时返回 null。
  Future<LibraryBootstrapResult?> create(String name) async {
    try {
      final access = await _accessGateway.create(name: name);
      if (access == null) {
        return null;
      }
      return initialize(access);
    } on LibraryAccessException catch (error) {
      await _discardSafely();
      return LibraryBootstrapFailure(error.failure);
    }
  }

  Future<LibraryBootstrapResult> initialize(LibraryAccess access) async {
    try {
      final metadata = await _repository.initialize(access);
      if (access.isPending) {
        await _accessGateway.commit();
      }
      return LibraryBootstrapReady(
        LibrarySession(
          access: LibraryAccess(
            token: access.token,
            displayPath: access.displayPath,
            isPending: false,
          ),
          metadata: metadata,
        ),
      );
    } on LibraryOperationException catch (error) {
      if (access.isPending) {
        await _discardSafely();
      }
      return LibraryBootstrapFailure(error.failure);
    } on LibraryAccessException catch (error) {
      await _discardSafely();
      return LibraryBootstrapFailure(error.failure);
    }
  }

  Future<void> discardPending() => _accessGateway.discard();

  Future<void> clearAccess() => _accessGateway.clear();

  Future<List<LibraryEntry>> listChildren(
    LibrarySession session, {
    String relativePath = '',
  }) {
    return _repository.listChildren(session.access, relativePath: relativePath);
  }

  Future<LibraryBootstrapResult> _inspect(LibraryAccess access) async {
    final inspection = await _repository.inspect(access);
    return switch (inspection) {
      LibraryInspectionReady(:final metadata) => LibraryBootstrapReady(
        LibrarySession(access: access, metadata: metadata),
      ),
      LibraryInspectionNeedsInitialization() =>
        LibraryBootstrapNeedsInitialization(access),
      LibraryInspectionFailure(:final failure) => LibraryBootstrapFailure(
        failure,
      ),
    };
  }

  Future<void> _discardSafely() async {
    try {
      await _accessGateway.discard();
    } on LibraryAccessException catch (_) {
      return;
    }
  }
}
