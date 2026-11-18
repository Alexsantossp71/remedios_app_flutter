import 'package:flutter_test/flutter_test.dart';
import 'package:remedios_app_flutter/services/database_key/database_key_service.dart';
import 'package:remedios_app_flutter/services/database_key/database_key_store.dart';
import 'package:remedios_app_flutter/services/database_key/in_memory_database_key_store.dart';

/// Cofre que registra chamadas para verificar o contrato de primeira criação.
class RecordingKeyStore implements DatabaseKeyStore {
  final InMemoryDatabaseKeyStore inner = InMemoryDatabaseKeyStore();
  int createCalls = 0;
  List<int>? lastCandidate;

  @override
  Future<List<int>?> readKey() => inner.readKey();

  @override
  Future<bool> createKeyIfAbsent(List<int> key) async {
    createCalls++;
    lastCandidate = List<int>.of(key);
    return inner.createKeyIfAbsent(key);
  }

  @override
  Future<void> deleteKey() => inner.deleteKey();
}

/// Cofre quebrado: simula material incompleto/corrompido que exige recuperação.
class BrokenKeyStore implements DatabaseKeyStore {
  @override
  Future<List<int>?> readKey() async {
    throw const DatabaseKeyRecoveryRequiredException(
      'Chave incompleta: restaure o envelope de recuperação.',
    );
  }

  @override
  Future<bool> createKeyIfAbsent(List<int> key) async {
    throw const DatabaseKeyRecoveryRequiredException(
      'Chave incompleta: restaure o envelope de recuperação.',
    );
  }

  @override
  Future<void> deleteKey() async {}
}

void main() {
  tearDown(() {
    DatabaseKeyService.instanceOverride = null;
  });

  test('resolveOrCreateKey gera 256 bits aleatórios no primeiro uso', () async {
    final store = RecordingKeyStore();
    DatabaseKeyService.resetInstanceForTesting(store: store);

    final key = await DatabaseKeyService.instance.resolveOrCreateKey();
    expect(key, hasLength(32));
    // Entropia: nem todos os bytes iguais.
    expect(key!.toSet().length, greaterThan(8));
    expect(store.createCalls, 1);
    expect(store.lastCandidate, key);
  });

  test('segunda resolução devolve a MESMA chave (nunca recria)', () async {
    final store = RecordingKeyStore();
    DatabaseKeyService.resetInstanceForTesting(store: store);

    final first = await DatabaseKeyService.instance.resolveOrCreateKey();
    final second = await DatabaseKeyService.instance.resolveOrCreateKey();
    expect(second, first);
    expect(store.createCalls, 1, reason: 'createKeyIfAbsent chamado uma vez');
  });

  test('concorrência: todas as resoluções chegam à mesma chave', () async {
    final store = RecordingKeyStore();
    DatabaseKeyService.resetInstanceForTesting(store: store);

    final keys = await Future.wait([
      DatabaseKeyService.instance.resolveOrCreateKey(),
      DatabaseKeyService.instance.resolveOrCreateKey(),
      DatabaseKeyService.instance.resolveOrCreateKey(),
    ]);
    expect(keys[0], keys[1]);
    expect(keys[1], keys[2]);

    final stored = await store.inner.readKey();
    expect(stored, keys[0]);
  });

  test('cofre quebrado lança recovery-required (nunca recria chave)', () async {
    DatabaseKeyService.resetInstanceForTesting(store: BrokenKeyStore());
    await expectLater(
      DatabaseKeyService.instance.resolveOrCreateKey(),
      throwsA(isA<DatabaseKeyRecoveryRequiredException>()),
    );
  });

  test(
    'InMemoryDatabaseKeyStore: primeira criação vence, resto perde',
    () async {
      final store = InMemoryDatabaseKeyStore();
      expect(await store.createKeyIfAbsent(List.filled(32, 1)), isTrue);
      expect(await store.createKeyIfAbsent(List.filled(32, 2)), isFalse);
      expect(await store.readKey(), List.filled(32, 1));
      expect(
        () => store.createKeyIfAbsent(List.filled(16, 3)),
        throwsArgumentError,
      );
    },
  );
}
