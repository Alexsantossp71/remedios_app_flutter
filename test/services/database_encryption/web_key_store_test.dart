import 'package:flutter_test/flutter_test.dart';
import 'package:remedios_app_flutter/services/database_key/database_key_store.dart';
import 'package:remedios_app_flutter/services/database_key/web_database_key_store.dart';
import 'package:remedios_app_flutter/services/database_key/web_key_storage.dart';

/// Simple in-memory localStorage substitute for the VM tests.
class _MapStorage implements WebKeyValueStorage {
  final Map<String, String> data = {};

  @override
  String? getItem(String key) => data[key];

  @override
  void setItem(String key, String value) => data[key] = value;

  @override
  void removeItem(String key) => data.remove(key);
}

const _password = 'senha-de-recuperacao-123';

void main() {
  late _MapStorage storage;
  late WebDatabaseKeyStore store;

  setUp(() {
    storage = _MapStorage();
    store = WebDatabaseKeyStore(storage: storage);
  });

  test('perfil novo: estado needsSetup e nenhuma chave disponível', () async {
    expect(store.state, DatabaseKeyState.needsSetup);
    expect(await store.readKey(), isNull);
  });

  test('setup cria envelope e resolve a chave na sessão', () async {
    final key = await store.setupWithPassword(_password);
    expect(key, hasLength(32));
    expect(store.state, DatabaseKeyState.unlocked);
    expect(await store.readKey(), key);
    expect(store.hasStoredEnvelope, isTrue);
    // O envelope armazenado é ciphertext (nunca a chave crua).
    final envelopeJson = storage.getItem(
      WebDatabaseKeyStore.envelopeStorageKey,
    )!;
    expect(envelopeJson, isNot(contains('key')));
  });

  test('sessão nova começa travada e desbloqueia com a senha', () async {
    final key = await store.setupWithPassword(_password);

    // Simula uma nova sessão (reload): chave apenas em memória se perde.
    final newSession = WebDatabaseKeyStore(storage: storage);
    expect(newSession.state, DatabaseKeyState.locked);
    expect(
      () => newSession.readKey(),
      throwsA(isA<DatabaseUnlockRequiredException>()),
    );

    final unlocked = await newSession.unlockWithPassword(_password);
    expect(unlocked, key);
    expect(newSession.state, DatabaseKeyState.unlocked);
    expect(await newSession.readKey(), key);
  });

  test(
    'senha incorreta lança DatabaseUnlockWrongPassword e mantém o envelope',
    () async {
      await store.setupWithPassword(_password);
      final newSession = WebDatabaseKeyStore(storage: storage);

      await expectLater(
        newSession.unlockWithPassword('outra-senha-longa-demais-456'),
        throwsA(isA<DatabaseUnlockWrongPasswordException>()),
      );
      // Nada foi apagado nem substituído.
      expect(newSession.hasStoredEnvelope, isTrue);
      expect(newSession.state, DatabaseKeyState.locked);
    },
  );

  test('setup recusa sobrescrever envelope existente', () async {
    await store.setupWithPassword(_password);
    expect(
      () => store.setupWithPassword('outra-senha-longa-demais-456'),
      throwsA(isA<DatabaseKeyRecoveryRequiredException>()),
    );
    expect(store.hasStoredEnvelope, isTrue);
  });

  test(
    'restauração em perfil limpo: envelope exportado + senha correta',
    () async {
      final original = await store.setupWithPassword(_password);
      final exported = store.exportEnvelopeJson()!;

      // Perfil limpo: novo storage vazio.
      final cleanStorage = _MapStorage();
      final cleanStore = WebDatabaseKeyStore(storage: cleanStorage);
      expect(cleanStore.state, DatabaseKeyState.needsSetup);

      final restored = await cleanStore.restoreEnvelope(exported, _password);
      expect(restored, original);
      expect(cleanStore.state, DatabaseKeyState.unlocked);
      expect(await cleanStore.readKey(), original);
    },
  );

  test('restauração com envelope adulterado falha e não grava nada', () async {
    await store.setupWithPassword(_password);
    var exported = store.exportEnvelopeJson()!;
    // Corrompe o JSON do envelope (adulteração de ciphertext).
    final json = exported.replaceAll('"ciphertext":"', '"ciphertext":"XX');
    final cleanStorage = _MapStorage();
    final cleanStore = WebDatabaseKeyStore(storage: cleanStorage);

    await expectLater(
      cleanStore.restoreEnvelope(json, _password),
      throwsA(isA<DatabaseKeyRecoveryRequiredException>()),
    );
    expect(cleanStorage.data, isEmpty);
  });

  test('restauração com senha incorreta falha e não grava nada', () async {
    await store.setupWithPassword(_password);
    final exported = store.exportEnvelopeJson()!;
    final cleanStorage = _MapStorage();
    final cleanStore = WebDatabaseKeyStore(storage: cleanStorage);

    await expectLater(
      cleanStore.restoreEnvelope(exported, 'senha-equivocada-longa-789'),
      throwsA(isA<DatabaseUnlockWrongPasswordException>()),
    );
    expect(cleanStorage.data, isEmpty);
  });

  test(
    'envelope corrompido no storage → recoveryRequired, nunca banco vazio',
    () async {
      await store.setupWithPassword(_password);
      storage.setItem(
        WebDatabaseKeyStore.envelopeStorageKey,
        '{"version": 1, "kdf": "pbkdf2-hmac-sha256", "iterations": 310000, '
        '"salt": "AAAA", "nonce": "AAA", "ciphertext": "AAAA", "mac": "AAA"}',
      );
      final newSession = WebDatabaseKeyStore(storage: storage);
      await expectLater(
        newSession.unlockWithPassword(_password),
        throwsA(isA<DatabaseKeyRecoveryRequiredException>()),
      );
    },
  );

  test(
    'deleteKey remove envelope e sessão (ciclo de vida explícito)',
    () async {
      await store.setupWithPassword(_password);
      await store.deleteKey();
      expect(store.hasStoredEnvelope, isFalse);
      expect(store.state, DatabaseKeyState.needsSetup);
      expect(await store.readKey(), isNull);
    },
  );

  test(
    'createKeyIfAbsent não é suportado na web (modelo de desbloqueio)',
    () async {
      expect(
        () => store.createKeyIfAbsent(List<int>.generate(32, (_) => 0)),
        throwsA(isA<UnsupportedError>()),
      );
    },
  );
}
