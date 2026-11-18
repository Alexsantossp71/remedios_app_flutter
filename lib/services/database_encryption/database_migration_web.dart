import 'package:sqflite_common/sqlite_api.dart';

import 'encryption_pragmas.dart';
import 'database_preservation.dart';

/// Result of a successful web legacy → encrypted migration.
class DatabaseMigrationWebResult {
  const DatabaseMigrationWebResult({
    required this.legacyVersion,
    required this.tablesBefore,
    required this.tablesAfter,
  });

  final int legacyVersion;
  final Map<String, TableSnapshot> tablesBefore;
  final Map<String, TableSnapshot> tablesAfter;

  List<String> get preservationProblems =>
      DatabasePreservation.compare(tablesBefore, tablesAfter);
}

/// Web migration engine.
///
/// On web the SQLite files live inside the browser storage (IndexedDB/OPFS
/// under the sqflite worker). Migration copies every row from the legacy
/// plaintext logical database into a NEW encrypted logical database opened
/// through the SQLite3MC VFS wrapper. The legacy database is never opened in
/// read-write mode, so it remains the preserved original in browser storage.
class DatabaseMigrationWeb {
  DatabaseMigrationWeb({this.copyBatchSize = 200});

  final int copyBatchSize;

  /// Runs the migration when needed.
  ///
  /// Returns null when there is nothing to do (target already exists, or no
  /// legacy database at all — fresh profile).
  Future<DatabaseMigrationWebResult?> migrateIfNeeded({
    required DatabaseFactory factory,
    required String legacyPath,
    required String encryptedPath,
    required List<int> key,
  }) async {
    if (key.length != 32) {
      throw ArgumentError('Database key must contain exactly 32 bytes.');
    }

    final targetExists = await factory.databaseExists(encryptedPath);
    if (targetExists) {
      return null;
    }
    final legacyExists = await factory.databaseExists(legacyPath);
    if (!legacyExists) {
      return null;
    }

    Database? legacyDb;
    Database? targetDb;
    try {
      // 1. Open the legacy database read-only (no PRAGMA key → plaintext
      //    passthrough through the multipleciphers VFS).
      legacyDb = await factory.openDatabase(
        legacyPath,
        options: OpenDatabaseOptions(singleInstance: false, readOnly: true),
      );
      final legacyVersionRow = await legacyDb.rawQuery('PRAGMA user_version');
      final legacyVersion =
          (legacyVersionRow.first['user_version'] as int?) ?? 0;

      final tablesBefore = await DatabasePreservation.snapshotTables(
        sqfliteRowSelector(legacyDb),
      );

      // 2. Create the encrypted target with the key applied and validated
      //    before any schema read.
      targetDb = await factory.openDatabase(
        encryptedPath,
        options: OpenDatabaseOptions(
          singleInstance: false,
          version: legacyVersion > 0 ? legacyVersion : 1,
          onCreate: (db, version) async {},
          onConfigure: (db) async {
            applyEncryptionPragmas(db, key);
            await validateEncryptedKeyOrThrow(db);
          },
        ),
      );

      // 3. Copy structure and data.
      final legacyForCopy = legacyDb;
      await targetDb.execute('PRAGMA foreign_keys = OFF');
      await targetDb.transaction((txn) async {
        await _copySchema(legacyForCopy, txn);
        await _copyData(legacyForCopy, txn);
      });
      await targetDb.execute('PRAGMA foreign_keys = ON');

      // 4. Validate integrity, foreign keys and preservation.
      final integrityRows = await targetDb.rawQuery('PRAGMA integrity_check');
      final integrity = integrityRows.first.values.first.toString();
      if (integrity != 'ok') {
        throw Exception('integrity_check falhou: $integrity');
      }
      final fkViolations = await targetDb.rawQuery('PRAGMA foreign_key_check');
      if (fkViolations.isNotEmpty) {
        throw Exception('foreign_key_check retornou violações.');
      }

      final tablesAfter = await DatabasePreservation.snapshotTables(
        sqfliteRowSelector(targetDb),
      );
      final problems = DatabasePreservation.compare(tablesBefore, tablesAfter);
      if (problems.isNotEmpty) {
        throw StateError(
          'Validação de preservação falhou: ${problems.join(' | ')}',
        );
      }

      final result = DatabaseMigrationWebResult(
        legacyVersion: legacyVersion,
        tablesBefore: tablesBefore,
        tablesAfter: tablesAfter,
      );

      await legacyDb.close();
      legacyDb = null;
      await targetDb.close();
      targetDb = null;
      return result;
    } catch (error) {
      // The encrypted target may be half-written: remove it so the next run
      // starts clean. The legacy database is never modified.
      try {
        await targetDb?.close();
      } catch (_) {}
      try {
        await legacyDb?.close();
      } catch (_) {}
      try {
        await factory.deleteDatabase(encryptedPath);
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> _copySchema(Database legacyDb, DatabaseExecutor txn) async {
    final objects = await legacyDb.rawQuery('''
      SELECT type, name, sql FROM sqlite_master
      WHERE sql IS NOT NULL
        AND name NOT LIKE 'sqlite_%'
      ORDER BY CASE type WHEN 'table' THEN 0 WHEN 'index' THEN 1 ELSE 2 END
    ''');
    for (final object in objects) {
      final sql = object['sql'] as String;
      await txn.execute(sql);
    }
  }

  Future<void> _copyData(Database legacyDb, DatabaseExecutor txn) async {
    for (final table in databaseV11Tables) {
      final exists = await legacyDb.rawQuery(
        "SELECT count(*) AS n FROM sqlite_master WHERE type = 'table' "
        "AND name = ?",
        [table],
      );
      if ((exists.first['n'] as int) == 0) {
        continue;
      }
      await _copyTable(legacyDb, txn, table);
    }
  }

  Future<void> _copyTable(
    Database legacyDb,
    DatabaseExecutor txn,
    String table,
  ) async {
    final columns = await legacyDb.rawQuery('PRAGMA table_info("$table")');
    final columnNames = columns.map((c) => c['name'] as String).toList();
    final columnList = columnNames.map((c) => '"$c"').join(', ');
    final placeholders = List.filled(columnNames.length, '?').join(', ');
    final insertSql =
        'INSERT INTO "$table" ($columnList) VALUES ($placeholders)';

    final rows = await legacyDb.rawQuery('SELECT $columnList FROM "$table"');
    for (var i = 0; i < rows.length; i += copyBatchSize) {
      final batch = rows.skip(i).take(copyBatchSize).toList();
      for (final row in batch) {
        final values = columnNames.map((c) => row[c]).toList();
        await txn.rawInsert(insertSql, values);
      }
    }
  }
}
