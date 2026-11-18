import '../database_key/database_key_store.dart';

/// Logical (web) or file (native) names used by the encrypted storage layer.
///
/// The legacy database keeps its original name and is never modified by the
/// migration; the encrypted database is a new, separate file. This is the
/// core of the no-data-loss guarantee: the original remains untouched until
/// an explicit retention policy removes it.
const String kLegacyDatabaseName = 'remedios_app.db';
const String kEncryptedDatabaseName = 'remedios_app_enc.db';

/// Marker written after a fully validated migration (metadata only — never
/// key material). Also used as the source of truth for "which database is
/// active" recovery decisions.
const String kEncryptionStateStorageKey = 'rnh.db.encryption.state';

/// Plan returned by [DatabaseEncryptionService.prepare] telling
/// `DatabaseService` exactly how to open the database.
class EncryptionOpenPlan {
  const EncryptionOpenPlan({
    required this.key,
    required this.databaseName,
    required this.freshInstall,
    required this.migrationAudit,
    required this.migratedLegacyVersion,
  });

  /// 256-bit key to open the encrypted database. Never logged.
  final List<int> key;

  /// File name (native) or logical name (web) to open.
  final String databaseName;

  /// True when nothing existed before (fresh install) — the full v11 schema
  /// must be created.
  final bool freshInstall;

  /// Non-sensitive audit metadata (counts per table, backup path, legacy
  /// version) recorded by a successful migration.
  final Map<String, Object?>? migrationAudit;

  /// Schema version the encrypted database was left at after a migration
  /// (equal to the legacy version). Null when no migration ran.
  final int? migratedLegacyVersion;
}

/// Platform facade that decides how the encrypted database is opened:
/// key resolution, legacy detection and the safe migration. Implemented per
/// platform (`*_io.dart` / `*_web.dart` conditional imports).
abstract interface class DatabaseEncryptionService {
  /// Resolves the key and performs the legacy → encrypted migration when
  /// needed.
  ///
  /// Returns null only when the platform is out of the delivery scope
  /// (iOS/macOS) — the caller then keeps the legacy plaintext behavior.
  ///
  /// Throws [DatabaseUnlockRequiredException] (web, session locked) and
  /// [DatabaseKeyRecoveryRequiredException] (key unrecoverable) without ever
  /// creating, deleting or overwriting database files.
  Future<EncryptionOpenPlan?> prepare();
}
