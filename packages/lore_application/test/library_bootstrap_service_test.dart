import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:test/test.dart';

void main() {
  const pendingAccess = LibraryAccess(
    token: '/tmp/library',
    displayPath: '/tmp/library',
    isPending: true,
  );
  const restoredAccess = LibraryAccess(
    token: '/tmp/library',
    displayPath: '/tmp/library',
    isPending: false,
  );
  final metadata = LibraryMetadata(
    schemaVersion: 1,
    id: const LibraryId('11111111-1111-4111-8111-111111111111'),
    createdAt: DateTime.utc(2026, 7, 17),
    updatedAt: DateTime.utc(2026, 7, 17),
  );

  test('restore requests selection when no bookmark exists', () async {
    final gateway = _FakeAccessGateway();
    final repository = _FakeLibraryRepository(
      inspection: const LibraryInspectionNeedsInitialization(),
      metadata: metadata,
    );
    final service = LibraryBootstrapService(
      accessGateway: gateway,
      repository: repository,
    );

    final result = await service.restore();

    expect(result, isA<LibraryBootstrapSelectionRequired>());
  });

  test('selected ordinary directory waits for initialization', () async {
    final gateway = _FakeAccessGateway(selectAccess: pendingAccess);
    final repository = _FakeLibraryRepository(
      inspection: const LibraryInspectionNeedsInitialization(),
      metadata: metadata,
    );
    final service = LibraryBootstrapService(
      accessGateway: gateway,
      repository: repository,
    );

    final result = await service.select();

    expect(result, isA<LibraryBootstrapNeedsInitialization>());
    expect(gateway.commitCount, 0);
    expect(gateway.discardCount, 0);
  });

  test('selected valid library commits pending access', () async {
    final gateway = _FakeAccessGateway(selectAccess: pendingAccess);
    final repository = _FakeLibraryRepository(
      inspection: LibraryInspectionReady(metadata),
      metadata: metadata,
    );
    final service = LibraryBootstrapService(
      accessGateway: gateway,
      repository: repository,
    );

    final result = await service.select();

    expect(result, isA<LibraryBootstrapReady>());
    final ready = result! as LibraryBootstrapReady;
    expect(ready.session.access.isPending, isFalse);
    expect(gateway.commitCount, 1);
  });

  test('failed selected library discards pending access', () async {
    final gateway = _FakeAccessGateway(selectAccess: pendingAccess);
    final repository = _FakeLibraryRepository(
      inspection: const LibraryInspectionFailure(
        LibraryFailure(
          code: LibraryFailureCode.metadataCorrupt,
          message: 'corrupt',
        ),
      ),
      metadata: metadata,
    );
    final service = LibraryBootstrapService(
      accessGateway: gateway,
      repository: repository,
    );

    final result = await service.select();

    expect(result, isA<LibraryBootstrapFailure>());
    expect(gateway.discardCount, 1);
  });

  test('initializing pending access writes metadata then commits', () async {
    final gateway = _FakeAccessGateway();
    final repository = _FakeLibraryRepository(
      inspection: const LibraryInspectionNeedsInitialization(),
      metadata: metadata,
    );
    final service = LibraryBootstrapService(
      accessGateway: gateway,
      repository: repository,
    );

    final result = await service.initialize(pendingAccess);

    expect(result, isA<LibraryBootstrapReady>());
    expect(repository.initializeCount, 1);
    expect(gateway.commitCount, 1);
  });

  test('restored valid library opens without another commit', () async {
    final gateway = _FakeAccessGateway(restoreAccess: restoredAccess);
    final repository = _FakeLibraryRepository(
      inspection: LibraryInspectionReady(metadata),
      metadata: metadata,
    );
    final service = LibraryBootstrapService(
      accessGateway: gateway,
      repository: repository,
    );

    final result = await service.restore();

    expect(result, isA<LibraryBootstrapReady>());
    expect(gateway.commitCount, 0);
  });

  test('created library directory initializes and commits once', () async {
    final gateway = _FakeAccessGateway(createAccess: pendingAccess);
    final repository = _FakeLibraryRepository(
      inspection: const LibraryInspectionNeedsInitialization(),
      metadata: metadata,
    );
    final service = LibraryBootstrapService(
      accessGateway: gateway,
      repository: repository,
    );

    final result = await service.create('我的书库');

    expect(result, isA<LibraryBootstrapReady>());
    final ready = result! as LibraryBootstrapReady;
    expect(ready.session.access.isPending, isFalse);
    expect(gateway.createdName, '我的书库');
    expect(repository.initializeCount, 1);
    expect(gateway.commitCount, 1);
  });

  test('cancelled creation writes nothing and does not commit', () async {
    final gateway = _FakeAccessGateway();
    final repository = _FakeLibraryRepository(
      inspection: const LibraryInspectionNeedsInitialization(),
      metadata: metadata,
    );
    final service = LibraryBootstrapService(
      accessGateway: gateway,
      repository: repository,
    );

    final result = await service.create('我的书库');

    expect(result, isNull);
    expect(gateway.createdName, '我的书库');
    expect(repository.initializeCount, 0);
    expect(gateway.commitCount, 0);
  });

  test('failed creation discards pending access', () async {
    final gateway = _FakeAccessGateway(
      createFailure: const LibraryAccessException(
        LibraryFailure(
          code: LibraryFailureCode.alreadyExists,
          message: 'exists',
        ),
      ),
    );
    final repository = _FakeLibraryRepository(
      inspection: const LibraryInspectionNeedsInitialization(),
      metadata: metadata,
    );
    final service = LibraryBootstrapService(
      accessGateway: gateway,
      repository: repository,
    );

    final result = await service.create('我的书库');

    expect(result, isA<LibraryBootstrapFailure>());
    final failure = result! as LibraryBootstrapFailure;
    expect(failure.failure.code, LibraryFailureCode.alreadyExists);
    expect(gateway.discardCount, 1);
  });

  test('creation failing to write metadata discards pending access', () async {
    final gateway = _FakeAccessGateway(createAccess: pendingAccess);
    final repository = _FakeLibraryRepository(
      inspection: const LibraryInspectionNeedsInitialization(),
      metadata: metadata,
      initializeFailure: const LibraryOperationException(
        LibraryFailure(code: LibraryFailureCode.notWritable, message: 'denied'),
      ),
    );
    final service = LibraryBootstrapService(
      accessGateway: gateway,
      repository: repository,
    );

    final result = await service.create('我的书库');

    expect(result, isA<LibraryBootstrapFailure>());
    expect(repository.initializeCount, 1);
    expect(gateway.discardCount, 1);
  });
}

final class _FakeAccessGateway implements LibraryAccessGateway {
  _FakeAccessGateway({
    this.restoreAccess,
    this.selectAccess,
    this.createAccess,
    this.createFailure,
  });

  final LibraryAccess? restoreAccess;
  final LibraryAccess? selectAccess;
  final LibraryAccess? createAccess;
  final LibraryAccessException? createFailure;
  String? createdName;
  int commitCount = 0;
  int discardCount = 0;

  @override
  Future<void> clear() async {}

  @override
  Future<void> commit() async {
    commitCount += 1;
  }

  @override
  Future<LibraryAccess?> create({required String name}) async {
    createdName = name;
    final failure = createFailure;
    if (failure != null) {
      throw failure;
    }
    return createAccess;
  }

  @override
  Future<void> discard() async {
    discardCount += 1;
  }

  @override
  Future<LibraryAccess?> restore() async => restoreAccess;

  @override
  Future<LibraryAccess?> select() async => selectAccess;
}

final class _FakeLibraryRepository implements LibraryRepository {
  _FakeLibraryRepository({
    required this.inspection,
    required this.metadata,
    this.initializeFailure,
  });

  final LibraryInspection inspection;
  final LibraryMetadata metadata;
  final LibraryOperationException? initializeFailure;
  int initializeCount = 0;

  @override
  Future<LibraryMetadata> initialize(LibraryAccess access) async {
    initializeCount += 1;
    final failure = initializeFailure;
    if (failure != null) {
      throw failure;
    }
    return metadata;
  }

  @override
  Future<LibraryInspection> inspect(LibraryAccess access) async => inspection;

  @override
  Future<List<LibraryEntry>> listChildren(
    LibraryAccess access, {
    String relativePath = '',
  }) async {
    return const [];
  }
}
