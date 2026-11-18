/// Cipher + key PRAGMAs shared by the native and web encrypted openers.
///
/// This file must stay free of native-only imports (`package:sqlite3`
/// native library, `dart:io`) so it compiles for the web worker/isolate too.
///
/// The key is passed as a raw 32-byte value and sent as a hex literal. The
/// hex string is built here and must NEVER be logged, printed or stored.
import 'package:sqflite_common/sqlite_api.dart' show Database;

const String kDatabaseCipherName = 'chacha20';

/// Applies the cipher + key PRAGMAs to a raw or sqflite connection.
void applyEncryptionPragmas(dynamic db, List<int> key) {
  if (key.length != 32) {
    throw ArgumentError('Database key must contain exactly 32 bytes.');
  }
  final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  db.execute("PRAGMA cipher = '$kDatabaseCipherName'");
  db.execute("PRAGMA key = \"x'$hex'\"");
}

/// Forces SQLite3MultipleCiphers to authenticate the key against the schema.
///
/// SQLite only reads the first page lazily: without this query a wrong key
/// would silently surface as "file is not a database" errors later, after
/// sqflite has already inspected the schema. Running it inside `onConfigure`
/// guarantees the key is validated BEFORE any schema read.
Future<void> validateEncryptedKeyOrThrow(dynamic db) async {
  // sqflite connections expose `rawQuery` (async); raw sqlite3/wasm
  // connections expose `select` (sync). The key validation must be awaited
  // on the sqflite path, otherwise the wrong-key failure only surfaces
  // later, after sqflite has already read the schema version.
  if (db is Database) {
    await db.rawQuery('SELECT count(*) FROM sqlite_master');
  } else {
    db.select('SELECT count(*) FROM sqlite_master');
  }
}
