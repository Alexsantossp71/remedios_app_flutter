import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:remedios_app_flutter/services/app_data_reset_service.dart';
import 'package:remedios_app_flutter/services/database_encryption/database_encryption_service.dart'
    show kEncryptedDatabaseName, kEncryptionStateStorageKey, kLegacyDatabaseName;
import 'package:remedios_app_flutter/services/database_key/database_key_service.dart';
import 'package:remedios_app_flutter/services/database_key/in_memory_database_key_store.dart';
import 'package:remedios_app_flutter/services/database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryDatabaseKeyStore keyStore;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    keyStore = InMemoryDatabaseKeyStore();
    DatabaseKeyService.resetInstanceForTesting(store: keyStore);
  });

  tearDown(() async {
    await DatabaseService.instance.close();
  });

  Future<List<int>> fakeKey() async {
    final key = List<int>.generate(32, (i) => i);
    await keyStore.createKeyIfAbsent(key);
    return key;
  }

  group('AppDataResetService.wipeAllDataAndVault', () {
    test('apaga os dois bancos, o cofre e o marcador de migração', () async {
      final deleted = <String>[];
      AppDataResetService.resetInstanceForTesting(
        databaseDeleter: (name) async => deleted.add(name),
      );
      await fakeKey();
      SharedPreferences.setMockInitialValues({
        kEncryptionStateStorageKey: '{"completedAt":"2026-01-01"}',
      });

      await AppDataResetService.instance.wipeAllDataAndVault();

      // Bancos: criptografado (ativo) + legado (pré-migração).
      expect(deleted, containsAll([kEncryptedDatabaseName, kLegacyDatabaseName]));
      // Cofre: DEK/envelope/espelho apagados — o estado-alvo é needsSetup.
      expect(await keyStore.readKey(), isNull);
      // Metadata de migração removida.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kEncryptionStateStorageKey), isNull);
    });

    test('falha isolada na deleção de banco não impede o cofre', () async {
      AppDataResetService.resetInstanceForTesting(
        databaseDeleter: (name) async {
          if (name == kEncryptedDatabaseName) {
            throw Exception('storage indisponível');
          }
        },
      );
      await fakeKey();

      // Não deve propagar: o apagamento é best-effort por etapa e o
      // resultado-alvo é "sem chave" mesmo com uma deleção falhando.
      await AppDataResetService.instance.wipeAllDataAndVault();

      expect(await keyStore.readKey(), isNull);
    });

    test('DatabaseKeyService.deleteVault apaga a chave do store', () async {
      await fakeKey();
      expect(await keyStore.readKey(), isNotNull);

      await DatabaseKeyService.instance.deleteVault();

      expect(await keyStore.readKey(), isNull);
    });
  });
}
