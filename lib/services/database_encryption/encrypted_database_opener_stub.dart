// Web stub for the native FFI encrypted opener.
//
// On web, databases are opened through `databaseFactoryWeb` (SQLite3MC
// worker) directly in `database_service.dart`; this stub only keeps the
// conditional-import graph web-safe. It re-exports the shared PRAGMA helpers,
// which are used by the web open path.

import 'package:sqflite_common/sqlite_api.dart' as sqflite;

export 'encryption_pragmas.dart'
    show
        applyEncryptionPragmas,
        kDatabaseCipherName,
        validateEncryptedKeyOrThrow;

/// Native-only helper. Never called on web (guarded by kIsWeb).
Future<sqflite.Database> openEncryptedSqfliteDatabase(
  String path, {
  required List<int> key,
  required int version,
  required Future<void> Function(sqflite.Database db, int version) onCreate,
  required Future<void> Function(
    sqflite.Database db,
    int oldVersion,
    int newVersion,
  )
  onUpgrade,
  Future<void> Function(sqflite.Database db)? extraOnConfigure,
  sqflite.DatabaseFactory? factory,
}) {
  throw UnsupportedError(
    'openEncryptedSqfliteDatabase is only available on native platforms.',
  );
}

/// Native-only helper. Never called on web (guarded by kIsWeb).
enum DatabaseFileFormat { plaintextSqlite, encryptedOrUnknown, notFound }
