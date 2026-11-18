import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../database_key/database_key_service.dart';
import '../database_key/database_key_store.dart';
import '../database_key/web_key_storage.dart';
import '../database_key/web_local_storage_binding.dart';
import '../database_factory_web.dart';
import 'database_encryption_service.dart';
import 'database_migration_web.dart';
import 'database_preservation.dart';

/// Web implementation: logical database names inside the browser storage
/// (IndexedDB via the SQLite3MC worker), migration state in localStorage and
/// the explicit unlock flow from [WebDatabaseKeyStore].
///
/// This file only compiles into web builds (conditional import from
/// `database_service.dart`), so importing the web database factory directly
/// mirrors the existing `database_service.dart` pattern.
class DatabaseEncryptionServiceWeb implements DatabaseEncryptionService {
  DatabaseEncryptionServiceWeb({required this.keyService});

  final DatabaseKeyService keyService;
  final DatabaseMigrationWeb _migration = DatabaseMigrationWeb();

  /// Storage facade (localStorage) for the non-sensitive migration marker.
  /// Injectable for tests.
  WebKeyValueStorage markerStorage = const LocalStorageKeyValueStorage();

  @override
  Future<EncryptionOpenPlan?> prepare() async {
    // 1. Key resolution. On web the session starts locked: readKey throws
    //    [DatabaseUnlockRequiredException] until the user unlocks. That
    //    exception must reach the unlock gate; nothing is created here.
    final key = await keyService.resolveKeyForOpen();
    if (key == null) {
      // Fresh profile with no envelope: setup must happen through the gate
      // (setupWithPassword) before any encrypted database is created.
      throw const DatabaseKeyRecoveryRequiredException(
        'Nenhum cofre de chaves está configurado neste navegador. Configure a '
        'senha de recuperação para proteger o banco.',
      );
    }

    // 2. Encrypted logical database already present: active database.
    final DatabaseFactory factory = databaseFactoryWeb;
    final targetExists = await factory.databaseExists(kEncryptedDatabaseName);
    if (targetExists) {
      return EncryptionOpenPlan(
        key: key,
        databaseName: kEncryptedDatabaseName,
        freshInstall: false,
        migrationAudit: null,
        migratedLegacyVersion: null,
      );
    }

    // 3. Legacy plaintext database present → migrate it into the encrypted
    //    logical database (legacy remains untouched in browser storage).
    final legacyExists = await factory.databaseExists(kLegacyDatabaseName);
    if (legacyExists) {
      final result = await _migration.migrateIfNeeded(
        factory: factory,
        legacyPath: kLegacyDatabaseName,
        encryptedPath: kEncryptedDatabaseName,
        key: key,
      );
      if (result == null) {
        return EncryptionOpenPlan(
          key: key,
          databaseName: kEncryptedDatabaseName,
          freshInstall: false,
          migrationAudit: null,
          migratedLegacyVersion: null,
        );
      }
      final audit = await _recordMigrationAudit(result);
      return EncryptionOpenPlan(
        key: key,
        databaseName: kEncryptedDatabaseName,
        freshInstall: false,
        migrationAudit: audit,
        migratedLegacyVersion: result.legacyVersion,
      );
    }

    // 4. Fresh profile: create the encrypted database on first open.
    return EncryptionOpenPlan(
      key: key,
      databaseName: kEncryptedDatabaseName,
      freshInstall: true,
      migrationAudit: null,
      migratedLegacyVersion: null,
    );
  }

  Future<Map<String, Object?>> _recordMigrationAudit(
    DatabaseMigrationWebResult result,
  ) async {
    final audit = <String, Object?>{
      'completedAt': DateTime.now().toUtc().toIso8601String(),
      'legacyVersion': result.legacyVersion,
      'countsBefore': DatabasePreservation.countsForAudit(result.tablesBefore),
      'countsAfter': DatabasePreservation.countsForAudit(result.tablesAfter),
    };
    try {
      markerStorage.setItem(kEncryptionStateStorageKey, jsonEncode(audit));
    } catch (_) {
      // Metadata is best-effort; the database state is authoritative.
    }
    return audit;
  }
}

/// Factory used by the conditional import in `database_service.dart`.
DatabaseEncryptionService createDatabaseEncryptionService(
  DatabaseKeyService keyService,
) {
  return DatabaseEncryptionServiceWeb(keyService: keyService);
}
