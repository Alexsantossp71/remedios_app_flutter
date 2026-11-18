import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database_key/database_key_service.dart';
import '../database_key/database_key_store.dart';
import 'database_encryption_service.dart';
import 'database_migration_io.dart';
import 'database_preservation.dart';
import 'encrypted_database_opener.dart' show verifySqliteEncryptionOrThrow;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show databaseFactoryFfi;

/// Native (Android) implementation: file-based detection, backup, migration
/// and swap. See [DatabaseMigrationIo] for the invariants.
class DatabaseEncryptionServiceIo implements DatabaseEncryptionService {
  DatabaseEncryptionServiceIo({
    required this.keyService,
    Future<String> Function()? directoryResolver,
  }) : _directoryResolver = directoryResolver;

  final DatabaseKeyService keyService;
  final Future<String> Function()? _directoryResolver;
  final DatabaseMigrationIo _migration = DatabaseMigrationIo();

  /// Resolves the documents directory used by `DatabaseService`, with the
  /// same fallback chain as the original `_initDatabase`.
  Future<String> resolveDirectory() async {
    final resolver = _directoryResolver;
    if (resolver != null) {
      return resolver();
    }
    try {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      return documentsDirectory.path;
    } catch (_) {
      // Fallback for tests or environments without path_provider.
      final databasesPath = await databaseFactoryFfi.getDatabasesPath();
      return databasesPath;
    }
  }

  @override
  Future<EncryptionOpenPlan?> prepare() async {
    // Scope guard: iOS/macOS are out of this delivery. They keep the legacy
    // plaintext database, unchanged.
    if (Platform.isIOS || Platform.isMacOS) {
      return null;
    }

    // 0. Fail-safe: refuse to run if the SQLite library ignores the cipher
    //    PRAGMAs (plaintext build). Data is never written pretending to be
    //    encrypted.
    verifySqliteEncryptionOrThrow();

    // 1. Key first — before touching any file. A missing/unrecoverable key
    //    must never lead to creating or deleting databases.
    final key = await keyService.resolveKeyForOpen();
    if (key == null) {
      throw const DatabaseKeyRecoveryRequiredException(
        'A chave de criptografia não está disponível. Restaure o envelope de '
        'recuperação; o banco original permanece intacto.',
      );
    }

    final directory = await resolveDirectory();
    final legacyPath = p.join(directory, kLegacyDatabaseName);
    final encryptedPath = p.join(directory, kEncryptedDatabaseName);

    final legacyFile = File(legacyPath);
    final encryptedFile = File(encryptedPath);

    // 2. Encrypted database already present: it is the active database.
    if (encryptedFile.existsSync()) {
      return EncryptionOpenPlan(
        key: key,
        databaseName: encryptedPath,
        freshInstall: false,
        migrationAudit: null,
        migratedLegacyVersion: null,
      );
    }

    // 3. Legacy present → run the safe migration (backup, copy, validate,
    //    atomic swap; the original file is never modified).
    if (legacyFile.existsSync()) {
      final result = await _migration.migrateIfNeeded(
        legacyPath: legacyPath,
        encryptedPath: encryptedPath,
        key: key,
      );
      if (result == null) {
        // Migrated by a concurrent flow between the existence checks.
        return EncryptionOpenPlan(
          key: key,
          databaseName: encryptedPath,
          freshInstall: false,
          migrationAudit: null,
          migratedLegacyVersion: null,
        );
      }
      final audit = await _recordMigrationAudit(result);
      return EncryptionOpenPlan(
        key: key,
        databaseName: encryptedPath,
        freshInstall: false,
        migrationAudit: audit,
        migratedLegacyVersion: result.legacyVersion,
      );
    }

    // 4. Fresh install: create the encrypted database with the full v11
    //    schema on first open.
    return EncryptionOpenPlan(
      key: key,
      databaseName: encryptedPath,
      freshInstall: true,
      migrationAudit: null,
      migratedLegacyVersion: null,
    );
  }

  /// Persists non-sensitive migration metadata for audit/recovery. Failure to
  /// write it does not fail the migration (the encrypted file itself is the
  /// source of truth).
  Future<Map<String, Object?>> _recordMigrationAudit(
    DatabaseMigrationResult result,
  ) async {
    final audit = <String, Object?>{
      'completedAt': DateTime.now().toUtc().toIso8601String(),
      'legacyVersion': result.legacyVersion,
      'backupPath': result.backupPath,
      'countsBefore': DatabasePreservation.countsForAudit(result.tablesBefore),
      'countsAfter': DatabasePreservation.countsForAudit(result.tablesAfter),
    };
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kEncryptionStateStorageKey, jsonEncode(audit));
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
  return DatabaseEncryptionServiceIo(keyService: keyService);
}
