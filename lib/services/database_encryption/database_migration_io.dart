import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqlite3/sqlite3.dart';
import 'package:synchronized/synchronized.dart';

import 'database_preservation.dart';
import 'encrypted_database_opener.dart';

/// Result of a successful legacy → encrypted migration.
class DatabaseMigrationResult {
  const DatabaseMigrationResult({
    required this.legacyVersion,
    required this.backupPath,
    required this.tablesBefore,
    required this.tablesAfter,
  });

  final int legacyVersion;
  final String backupPath;
  final Map<String, TableSnapshot> tablesBefore;
  final Map<String, TableSnapshot> tablesAfter;

  List<String> get preservationProblems =>
      DatabasePreservation.compare(tablesBefore, tablesAfter);
}

/// Failure of the encryption migration. The original database is always left
/// untouched; a partial temporary database is removed.
class DatabaseMigrationFailedException implements Exception {
  const DatabaseMigrationFailedException(
    this.message, [
    this.cause,
    this.stackTrace,
  ]);

  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() =>
      'DatabaseMigrationFailedException: $message${cause == null ? '' : ' (causa: $cause)'}';
}

/// Native (Android/desktop) migration engine: copies a plaintext legacy
/// SQLite database into a NEW encrypted SQLite3MultipleCiphers file, using a
/// consistent backup, full validation and an atomic swap.
///
/// Invariants (mission-critical):
/// - The legacy file is never modified, renamed or deleted by this class.
/// - Any failure removes only temporary artifacts and leaves the legacy file
///   exactly as it was.
/// - A process interruption at any point is recoverable: the next run detects
///   the stale temporary file and restarts cleanly.
class DatabaseMigrationIo {
  /// In-process serialization for concurrent migrations (fcntl file locks
  /// do not conflict within the same process). Cross-process safety is kept
  /// by the migration lock file.
  static final Lock _inProcessLock = Lock();

  DatabaseMigrationIo({this.copyBatchSize = 200});

  /// Rows per INSERT batch during the copy phase.
  final int copyBatchSize;

  /// Test-only: simulates a process interruption right after the schema+
  /// data copy, before validation/swap. Never set in production flows.
  @visibleForTesting
  bool failAfterCopyForTesting = false;

  /// Runs the migration when needed. Returns null when there is nothing to
  /// do (encrypted database already present, or no legacy database at all).
  Future<DatabaseMigrationResult?> migrateIfNeeded({
    required String legacyPath,
    required String encryptedPath,
    required List<int> key,
  }) async {
    if (key.length != 32) {
      throw ArgumentError('Database key must contain exactly 32 bytes.');
    }

    final legacyFile = File(legacyPath);
    final encryptedFile = File(encryptedPath);

    // Nothing to migrate: fresh install.
    if (!legacyFile.existsSync() && !encryptedFile.existsSync()) {
      return null;
    }
    // Migration already completed in a previous run.
    if (encryptedFile.existsSync()) {
      return null;
    }
    // Legacy exists but encrypted does not: run the migration.
    if (!legacyFile.existsSync()) {
      return null;
    }

    final format = detectSqliteFileFormat(legacyPath);
    if (format != DatabaseFileFormat.plaintextSqlite) {
      throw DatabaseMigrationFailedException(
        'O arquivo do banco legado não é um SQLite em texto claro e não pode '
        'ser migrado com segurança. Nenhum dado foi alterado.',
      );
    }

    // Serialize concurrent calls inside this isolate first, then take the
    // OS-level file lock for cross-process safety.
    return _inProcessLock.synchronized<DatabaseMigrationResult?>(
      () => _withMigrationLock('$encryptedPath.migration.lock', () async {
        // Double-check under the lock to block concurrent migrations.
        if (encryptedFile.existsSync()) {
          return null;
        }
        return _migrate(
          legacyPath: legacyPath,
          encryptedPath: encryptedPath,
          key: key,
        );
      }),
    );
  }

  Future<DatabaseMigrationResult> _migrate({
    required String legacyPath,
    required String encryptedPath,
    required List<int> key,
  }) async {
    final legacyFile = File(legacyPath);
    final tempPath = '$encryptedPath.migrating.tmp';

    // 1. Consistent, verifiable backup of the original (file + WAL/journal).
    final backupPath = await _createVerifiedBackup(legacyFile);

    Database? legacyDb;
    Database? tempDb;
    try {
      // 2. Open the legacy database read-only (plaintext passthrough on the
      //    multipleciphers VFS/lib: no PRAGMA key = no encryption applied).
      legacyDb = sqlite3.open(legacyPath, mode: OpenMode.readOnly);
      final legacyVersion = _readUserVersion(legacyDb);

      // Tables actually present in the legacy schema, intersected with the
      // known app tables (older schema versions lack newer tables).
      final tablesToValidate = _legacyTablesToValidate(legacyDb);

      // 3. Snapshot before (counts + ids per table).
      final tablesBefore = await DatabasePreservation.snapshotTables(
        rawSqliteRowSelector(legacyDb),
        tables: tablesToValidate,
      );

      // 4. Prepare a clean temporary encrypted database.
      final tempFile = File(tempPath);
      if (tempFile.existsSync()) {
        // Leftover from an interrupted run: safe to remove, it was never the
        // source of truth.
        tempFile.deleteSync();
      }

      tempDb = sqlite3.open(tempPath);
      applyEncryptionPragmas(tempDb, key);
      await validateEncryptedKeyOrThrow(tempDb);

      // 5. Copy structure and data inside one transaction, without FK
      //    enforcement (parent rows are copied before children anyway).
      tempDb.execute('PRAGMA foreign_keys = OFF');
      tempDb.execute('BEGIN');
      _copySchema(legacyDb, tempDb);
      _copyData(legacyDb, tempDb);
      tempDb.execute('COMMIT');

      // Preserve the legacy schema version so sqflite runs the normal
      // onUpgrade chain when the app later opens this file at version 11
      // (and at every future schema version).
      final effectiveVersion = legacyVersion > 0 ? legacyVersion : 1;
      tempDb.execute('PRAGMA user_version = $effectiveVersion');

      // Test-only interruption point (simulates a killed process).
      if (failAfterCopyForTesting) {
        throw DatabaseMigrationFailedException(
          'Interrupção simulada após a cópia (teste).',
        );
      }

      // 6. Re-enable FKs and validate integrity + relationships.
      tempDb.execute('PRAGMA foreign_keys = ON');
      final integrity =
          (tempDb.select('PRAGMA integrity_check').first.values.first
              as String);
      if (integrity != 'ok') {
        throw DatabaseMigrationFailedException(
          'O banco temporário criptografado falhou na verificação de '
          'integridade: $integrity',
        );
      }
      final fkViolations = tempDb.select('PRAGMA foreign_key_check');
      if (fkViolations.isNotEmpty) {
        throw DatabaseMigrationFailedException(
          'O banco temporário criptografado possui violações de chave '
          'estrangeira.',
        );
      }

      // 7. Snapshot after and compare — hard gate: any difference aborts.
      final tablesAfter = await DatabasePreservation.snapshotTables(
        rawSqliteRowSelector(tempDb),
        tables: tablesToValidate,
      );
      final problems = DatabasePreservation.compare(tablesBefore, tablesAfter);
      if (problems.isNotEmpty) {
        throw DatabaseMigrationFailedException(
          'A validação de preservação falhou. O banco original não foi '
          'alterado. Problemas: ${problems.join(' | ')}',
        );
      }

      // 8. Close both files before the swap.
      tempDb.dispose();
      tempDb = null;
      legacyDb.dispose();
      legacyDb = null;

      // 9. Atomic swap: temporary file becomes the encrypted database. The
      //    legacy file keeps its original name and content as the preserved
      //    original until the retention policy removes it.
      final renamed = tempFile.renameSync(encryptedPath);
      if (!renamed.existsSync()) {
        throw DatabaseMigrationFailedException(
          'Falha ao finalizar a troca do arquivo criptografado.',
        );
      }

      return DatabaseMigrationResult(
        legacyVersion: legacyVersion,
        backupPath: backupPath,
        tablesBefore: tablesBefore,
        tablesAfter: tablesAfter,
      );
    } on DatabaseMigrationFailedException {
      await _cleanupAfterFailure(tempDb, tempPath);
      rethrow;
    } catch (error, stackTrace) {
      await _cleanupAfterFailure(tempDb, tempPath);
      throw DatabaseMigrationFailedException(
        'A migração para o banco criptografado falhou. O banco original '
        'permanece intacto.',
        error,
        stackTrace,
      );
    }
  }

  // ---- helpers ----

  Future<T> _withMigrationLock<T>(
    String lockPath,
    Future<T> Function() action,
  ) async {
    final lockFile = File(lockPath);
    lockFile.parent.createSync(recursive: true);
    final raf = lockFile.openSync(mode: FileMode.writeOnlyAppend);
    try {
      // Non-blocking acquire with retry: concurrent callers wait without
      // freezing the isolate event loop. The OS releases the lock if the
      // process dies mid-migration.
      var acquired = false;
      var attempts = 0;
      while (!acquired) {
        try {
          raf.lockSync(FileLock.exclusive);
          acquired = true;
        } on FileSystemException {
          attempts++;
          if (attempts > 600) {
            // ~30 s aguardando outra migração: desiste sem tocar em nada.
            throw const DatabaseMigrationFailedException(
              'Outra migração do banco está em andamento. Nenhum arquivo foi '
              'alterado; tente novamente em instantes.',
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
      try {
        return await action();
      } finally {
        raf.unlockSync();
      }
    } finally {
      raf.closeSync();
    }
  }

  Future<String> _createVerifiedBackup(File legacyFile) async {
    final backupDir = Directory(
      '${legacyFile.parent.path}/remedios_app_backup_pre_encryption',
    );
    if (!backupDir.existsSync()) {
      backupDir.createSync(recursive: true);
    }
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('.', '');
    final backupPath = '${backupDir.path}/remedios_app.db.backup-$stamp';

    // Copy database file first, then sidecar files (WAL/journal), so the
    // backup forms a consistent set.
    legacyFile.copySync(backupPath);
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final sidecar = File('${legacyFile.path}$suffix');
      if (sidecar.existsSync()) {
        sidecar.copySync('$backupPath$suffix');
      }
    }

    // Verify the backup: same size and same header as the original.
    final original = legacyFile.readAsBytesSync();
    final backup = File(backupPath).readAsBytesSync();
    if (backup.length != original.length) {
      throw DatabaseMigrationFailedException(
        'A cópia de segurança do banco legado ficou inconsistente '
        '(tamanho divergente). A migração foi abortada.',
      );
    }

    // The backup must open as plaintext and expose the same schema.
    final verifyDb = sqlite3.open(backupPath, mode: OpenMode.readOnly);
    try {
      final tables = verifyDb.select(
        "SELECT count(*) AS n FROM sqlite_master WHERE type = 'table'",
      );
      if ((tables.first['n'] as int) <= 0) {
        throw DatabaseMigrationFailedException(
          'A cópia de segurança do banco legado não contém tabelas. '
          'A migração foi abortada.',
        );
      }
    } finally {
      verifyDb.dispose();
    }
    return backupPath;
  }

  /// User tables of the legacy database that are part of the known app
  /// schema, in foreign-key-safe copy order.
  List<String> _legacyTablesToValidate(Database legacyDb) {
    final rows = legacyDb.select('''
      SELECT name FROM sqlite_master
      WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
    ''');
    final legacyTables = rows.map((r) => r['name'] as String).toSet();
    return databaseV11Tables
        .where((table) => legacyTables.contains(table))
        .toList();
  }

  int _readUserVersion(Database db) {
    final row = db.select('PRAGMA user_version');
    return row.first['user_version'] as int;
  }

  /// Copies CREATE TABLE / INDEX / TRIGGER statements from the legacy schema.
  void _copySchema(Database legacyDb, Database tempDb) {
    final objects = legacyDb.select('''
      SELECT type, name, sql FROM sqlite_master
      WHERE sql IS NOT NULL
        AND name NOT LIKE 'sqlite_%'
      ORDER BY CASE type WHEN 'table' THEN 0 WHEN 'index' THEN 1 ELSE 2 END
    ''');
    for (final object in objects) {
      final sql = object['sql'] as String;
      tempDb.execute(sql);
    }
  }

  /// Copies rows of every user table in foreign-key-safe order.
  void _copyData(Database legacyDb, Database tempDb) {
    for (final table in databaseV11Tables) {
      final exists = legacyDb.select(
        "SELECT count(*) AS n FROM sqlite_master WHERE type = 'table' "
        "AND name = ?",
        [table],
      );
      if ((exists.first['n'] as int) == 0) {
        continue; // older schema version without this table
      }
      _copyTable(legacyDb, tempDb, table);
    }
  }

  void _copyTable(Database legacyDb, Database tempDb, String table) {
    final columns = legacyDb.select('PRAGMA table_info("$table")');
    final columnNames = columns.map((c) => c['name'] as String).toList();
    final columnList = columnNames.map((c) => '"$c"').join(', ');
    final placeholders = List.filled(columnNames.length, '?').join(', ');
    final insertSql =
        'INSERT INTO "$table" ($columnList) VALUES ($placeholders)';

    final rows = legacyDb.select('SELECT $columnList FROM "$table"');
    for (var i = 0; i < rows.length; i += copyBatchSize) {
      final batch = rows.skip(i).take(copyBatchSize);
      final statement = tempDb.prepare(insertSql);
      try {
        for (final row in batch) {
          final values = columnNames.map((c) => row[c]).toList();
          statement.execute(values);
        }
      } finally {
        statement.dispose();
      }
    }
  }

  Future<void> _cleanupAfterFailure(Database? tempDb, String tempPath) async {
    try {
      tempDb?.dispose();
    } catch (_) {}
    try {
      final tempFile = File(tempPath);
      if (tempFile.existsSync()) tempFile.deleteSync();
    } catch (_) {}
    // Nothing else: the legacy database and its backup remain untouched.
  }
}
