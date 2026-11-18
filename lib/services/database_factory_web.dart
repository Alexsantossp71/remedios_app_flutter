// Web-specific database factory.
//
// Uses sqflite_common_ffi_web with a custom shared worker that opens every
// database through the SQLite3MultipleCiphers VFS wrapper
// (`multipleciphers-<fs>`). The WASM artifact served as `web/sqlite3.wasm` is
// the official `sqlite3mc.wasm` build for the pinned `sqlite3` package
// version, so the worker and the databases are encryption-capable.
//
// Without a PRAGMA key, SQLite3MultipleCiphers reads/writes plaintext
// databases transparently; with a key, the file is encrypted (ChaCha20).
// This is what makes the legacy → encrypted migration possible in the same
// worker.

import 'package:sqflite_common/sqlite_api.dart' show DatabaseFactory;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Web database factory instance backed by the SQLite3MC worker.
///
/// The worker is compiled from `web/sqlite3mc_shared_worker.dart` into
/// `web/sqlite3_mc_sw.js` by the CI (`dart compile js`). It loads
/// `web/sqlite3.wasm` (the SQLite3MultipleCiphers artifact) and registers the
/// encrypted VFS wrapper for every opened database.
final DatabaseFactory databaseFactoryWeb = createDatabaseFactoryFfiWeb(
  options: SqfliteFfiWebOptions(sharedWorkerUri: Uri.parse('sqlite3_mc_sw.js')),
);

/// No-op initialization for web (kept for compatibility).
void initializeDatabaseFactory() {
  // databaseFactoryWeb is ready to use; the worker loads the WASM lazily.
}
