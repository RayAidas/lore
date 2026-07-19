import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_platform_adapters/lore_platform_adapters.dart';
import 'package:lore_storage/lore_storage.dart';

import '../workspace/workspace_controller.dart';

final idGeneratorProvider = Provider<IdGenerator>((ref) {
  return const UuidIdGenerator();
});

final clockProvider = Provider<Clock>((ref) {
  return const SystemClock();
});

final libraryMutationCoordinatorProvider = Provider<LibraryMutationCoordinator>(
  (ref) => LibraryMutationCoordinator(),
);

final libraryAccessGatewayProvider = Provider<LibraryAccessGateway>((ref) {
  if (Platform.isMacOS) {
    return MacOsLibraryAccessGateway();
  }
  if (Platform.isAndroid) {
    return AndroidSafLibraryAccessGateway();
  }
  return const UnsupportedLibraryAccessGateway();
});

final libraryStorageFactoryProvider = Provider<LibraryStorageFactory>((ref) {
  if (Platform.isAndroid) {
    return AndroidSafStorageFactory();
  }
  return LocalDirectoryStorageFactory(
    fileOperationsGateway: Platform.isMacOS
        ? MacOsLibraryFileOperationsGateway()
        : null,
  );
});

final libraryAssetServiceProvider = Provider<LibraryAssetService>((ref) {
  return LibraryAssetService(ref.watch(libraryStorageFactoryProvider));
});

final storageBackedLibraryRepositoryProvider =
    Provider<StorageBackedLibraryRepository>((ref) {
      return StorageBackedLibraryRepository(
        storageFactory: ref.watch(libraryStorageFactoryProvider),
        idGenerator: ref.watch(idGeneratorProvider),
        clock: ref.watch(clockProvider),
      );
    });

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  return ref.watch(storageBackedLibraryRepositoryProvider);
});

final libraryTreeRepositoryProvider = Provider<LibraryTreeRepository>((ref) {
  return ref.watch(storageBackedLibraryRepositoryProvider);
});

final documentRepositoryProvider = Provider<DocumentRepository>((ref) {
  return ref.watch(storageBackedLibraryRepositoryProvider);
});

final novelRepositoryProvider = Provider<NovelRepository>((ref) {
  return ref.watch(storageBackedLibraryRepositoryProvider);
});

final contentTreeRepositoryProvider = Provider<ContentTreeRepository>((ref) {
  return ref.watch(storageBackedLibraryRepositoryProvider);
});

final novelStructureServiceProvider = Provider<NovelStructureService>((ref) {
  return NovelStructureService(
    novelRepository: ref.watch(novelRepositoryProvider),
    contentTreeRepository: ref.watch(contentTreeRepositoryProvider),
    mutationCoordinator: ref.watch(libraryMutationCoordinatorProvider),
  );
});

final writingProgressRepositoryProvider = Provider<WritingProgressRepository>((
  ref,
) {
  return SharedPreferencesWritingProgressRepository();
});

final novelOverviewServiceProvider = Provider<NovelOverviewService>((ref) {
  return NovelOverviewService(
    novelRepository: ref.watch(novelRepositoryProvider),
    documentRepository: ref.watch(documentRepositoryProvider),
    clock: ref.watch(clockProvider),
    writingProgressRepository: ref.watch(writingProgressRepositoryProvider),
  );
});

final trashRepositoryProvider = Provider<TrashRepository>((ref) {
  return ref.watch(storageBackedLibraryRepositoryProvider);
});

final libraryRevealGatewayProvider = Provider<LibraryRevealGateway?>((ref) {
  if (Platform.isMacOS) {
    return MacOsLibraryRevealGateway();
  }
  return null;
});

final workspaceSessionRepositoryProvider = Provider<WorkspaceSessionRepository>(
  (ref) => const SharedPreferencesWorkspaceSessionRepository(),
);

final libraryWorkspaceServiceProvider = Provider<LibraryWorkspaceService>((
  ref,
) {
  return LibraryWorkspaceService(
    treeRepository: ref.watch(libraryTreeRepositoryProvider),
    documentRepository: ref.watch(documentRepositoryProvider),
    sessionRepository: ref.watch(workspaceSessionRepositoryProvider),
    mutationCoordinator: ref.watch(libraryMutationCoordinatorProvider),
  );
});

final workspaceControllerProvider = Provider.autoDispose
    .family<WorkspaceController, LibrarySession>((ref, session) {
      final controller = WorkspaceController(
        session: session,
        service: ref.watch(libraryWorkspaceServiceProvider),
        novelStructureService: ref.watch(novelStructureServiceProvider),
        novelOverviewService: ref.watch(novelOverviewServiceProvider),
        writingProgressRepository: ref.watch(writingProgressRepositoryProvider),
        trashRepository: ref.watch(trashRepositoryProvider),
        revealGateway: ref.watch(libraryRevealGatewayProvider),
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

final libraryBootstrapServiceProvider = Provider<LibraryBootstrapService>((
  ref,
) {
  return LibraryBootstrapService(
    accessGateway: ref.watch(libraryAccessGatewayProvider),
    repository: ref.watch(libraryRepositoryProvider),
  );
});

final libraryControllerProvider =
    AsyncNotifierProvider<LibraryController, LibraryUiState>(
      LibraryController.new,
    );

sealed class LibraryUiState {
  const LibraryUiState();
}

final class LibraryNeedsSelectionState extends LibraryUiState {
  const LibraryNeedsSelectionState();
}

final class LibraryNeedsInitializationState extends LibraryUiState {
  const LibraryNeedsInitializationState({required this.access, this.previous});

  final LibraryAccess access;
  final LibraryReadyState? previous;
}

final class LibraryReadyState extends LibraryUiState {
  const LibraryReadyState(this.session);

  final LibrarySession session;
}

final class LibraryErrorState extends LibraryUiState {
  const LibraryErrorState({required this.failure, this.previous});

  final LibraryFailure failure;
  final LibraryReadyState? previous;
}

final class LibraryController extends AsyncNotifier<LibraryUiState> {
  LibraryBootstrapService get _service {
    return ref.read(libraryBootstrapServiceProvider);
  }

  @override
  Future<LibraryUiState> build() async {
    return _mapResult(await _service.restore());
  }

  Future<LibraryUiState?> selectDirectory() async {
    final previous = _currentReadyState();
    state = const AsyncLoading();
    final result = await _service.select();
    if (result == null) {
      final restored = previous ?? const LibraryNeedsSelectionState();
      state = AsyncData(restored);
      return null;
    }
    final next = _mapResult(result, previous: previous);
    state = AsyncData(next);
    return next;
  }

  Future<void> initialize(LibraryNeedsInitializationState current) async {
    state = const AsyncLoading();
    final result = await _service.initialize(current.access);
    state = AsyncData(_mapResult(result, previous: current.previous));
  }

  Future<void> cancelInitialization(
    LibraryNeedsInitializationState current,
  ) async {
    if (current.access.isPending) {
      await _service.discardPending();
    } else {
      await _service.clearAccess();
    }
    state = AsyncData(current.previous ?? const LibraryNeedsSelectionState());
  }

  Future<void> retryRestore() async {
    state = const AsyncLoading();
    state = AsyncData(_mapResult(await _service.restore()));
  }

  void returnToPrevious(LibraryReadyState previous) {
    state = AsyncData(previous);
  }

  Future<List<LibraryEntry>> listChildren(
    LibrarySession session, {
    String relativePath = '',
  }) {
    return _service.listChildren(session, relativePath: relativePath);
  }

  LibraryReadyState? _currentReadyState() {
    final current = state.value;
    return switch (current) {
      LibraryReadyState ready => ready,
      LibraryNeedsInitializationState(:final previous) => previous,
      LibraryErrorState(:final previous) => previous,
      _ => null,
    };
  }

  LibraryUiState _mapResult(
    LibraryBootstrapResult result, {
    LibraryReadyState? previous,
  }) {
    return switch (result) {
      LibraryBootstrapSelectionRequired() => const LibraryNeedsSelectionState(),
      LibraryBootstrapNeedsInitialization(:final access) =>
        LibraryNeedsInitializationState(access: access, previous: previous),
      LibraryBootstrapReady(:final session) => LibraryReadyState(session),
      LibraryBootstrapFailure(:final failure) => LibraryErrorState(
        failure: failure,
        previous: previous,
      ),
    };
  }
}
