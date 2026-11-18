import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:sqflite_common/sqlite_api.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show databaseFactoryFfi;
import 'package:sqlite3/sqlite3.dart';

import 'encryption_pragmas.dart';

export 'encryption_pragmas.dart'
    show
        applyEncryptionPragmas,
        kDatabaseCipherName,
        validateEncryptedKeyOrThrow;

/// Opens an encrypted database through sqflite_common_ffi with the key
/// applied and validated in `onConfigure`, before any schema read.
///
/// [extraOnConfigure] runs after the encryption PRAGMAs (foreign keys, etc.).
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
  final effectiveFactory = factory ?? databaseFactoryFfi;
  return effectiveFactory.openDatabase(
    path,
    options: sqflite.OpenDatabaseOptions(
      version: version,
      onCreate: onCreate,
      onUpgrade: onUpgrade,
      onConfigure: (db) async {
        applyEncryptionPragmas(db, key);
        await validateEncryptedKeyOrThrow(db);
        await extraOnConfigure?.call(db);
      },
    ),
  );
}

/// Thrown when the SQLite library in use does NOT support encryption.
///
/// This is a fail-safe guard: a plaintext SQLite build silently ignores the
/// cipher/key PRAGMAs, which would store health data unencrypted while the
/// app believes it is protected. The app must refuse to open the encrypted
/// database in that case instead of writing plaintext data.
class DatabaseEncryptionUnavailableException implements Exception {
  const DatabaseEncryptionUnavailableException(this.message);

  final String message;

  @override
  String toString() => 'DatabaseEncryptionUnavailableException: $message';
}

/// Probes that the loaded SQLite library is encryption-capable by writing a
/// tiny throwaway database and inspecting its on-disk header.
///
/// A plaintext SQLite build ignores `PRAGMA cipher`/`PRAGMA key`, so this
/// probe is the definitive runtime check (there is no reliable capability
/// pragma in SQLite3MultipleCiphers).
void verifySqliteEncryptionOrThrow() {
  final random = Random.secure();
  final probeDir = Directory.systemTemp.createTempSync('rnh-enc-probe-');
  final probePath = '${probeDir.path}/probe.db';
  final key = List<int>.generate(32, (_) => random.nextInt(256));
  var db = sqlite3.open(probePath);
  try {
    applyEncryptionPragmas(db, key);
    db.execute('CREATE TABLE probe (v TEXT NOT NULL)');
    db.execute("INSERT INTO probe VALUES ('probe')");
  } finally {
    db.dispose();
  }

  final format = detectSqliteFileFormat(probePath);
  probeDir.deleteSync(recursive: true);
  if (format != DatabaseFileFormat.encryptedOrUnknown) {
    throw const DatabaseEncryptionUnavailableException(
      'A biblioteca SQLite desta instalação não suporta criptografia. O app '
      'não gravará dados de saúde sem proteção; o banco original permanece '
      'intacto.',
    );
  }
}

/// Result of detecting the on-disk format of a SQLite database file.
enum DatabaseFileFormat { plaintextSqlite, encryptedOrUnknown, notFound }

/// Detects whether [path] is a plaintext SQLite file by reading its header.
///
/// An encrypted SQLite3MultipleCiphers file never contains the standard
/// "SQLite format 3" magic in the first 16 bytes.
DatabaseFileFormat detectSqliteFileFormat(String path) {
  final file = File(path);
  if (!file.existsSync()) return DatabaseFileFormat.notFound;
  final raf = file.openSync();
  try {
    final length = raf.lengthSync();
    if (length < 16) return DatabaseFileFormat.encryptedOrUnknown;
    final header = raf.readSync(16);
    var actual = '';
    for (final byte in header) {
      actual += String.fromCharCode(byte);
    }
    const magic = 'SQLite format 3\u0000';
    return actual == magic
        ? DatabaseFileFormat.plaintextSqlite
        : DatabaseFileFormat.encryptedOrUnknown;
  } finally {
    raf.closeSync();
  }
}

/// Shared open helper surface for conditional imports: the web build never
/// calls the FFI opener, so a stub keeps the compile graph web-safe.
FutureOr<sqflite.Database> Function(
  String, {
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
})
get openEncryptedSqfliteDatabaseFn => openEncryptedSqfliteDatabase;
