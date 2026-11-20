// Mobile/Desktop database factory.
//
// Android (in scope for the encryption delivery) and Windows/Linux use
// `sqflite_common_ffi`, whose SQLite library is compiled by the build hook as
// SQLite3MultipleCiphers (ChaCha20) — see the `hooks.user_defines.sqlite3`
// section of pubspec.yaml. iOS/macOS are out of scope for this delivery and
// keep the standard sqflite plugin (plaintext, unchanged behavior).

import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Compile-time stub for [databaseFactoryWeb] (only defined on web).
/// Never used at runtime: access is guarded by `kIsWeb`.
final databaseFactoryWeb = databaseFactory;

/// True when the current native platform must use the FFI factory backed by
/// the SQLite3MultipleCiphers build. iOS/macOS are out of scope for this
/// delivery and keep the standard sqflite plugin factory.
bool get usesSqlite3McFfi => !Platform.isIOS && !Platform.isMacOS;

/// Initialize database factory per platform.
void initializeDatabaseFactory() {
  if (usesSqlite3McFfi) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}

/// Initialize the FFI database factory unconditionally for tests.
///
/// [initializeDatabaseFactory] skips iOS/macOS (out of scope for the
/// encryption delivery), which leaves `databaseFactory` unset on macOS and
/// breaks the in-memory database used by tests. Test setup needs a working
/// factory on every desktop platform CI runs on (P3-1 multi-OS matrix), so
/// this forces `sqflite_common_ffi` regardless of the production gate.
/// Production code must not call this — use [initializeDatabaseFactory].
void initializeDatabaseFactoryForTesting() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}
