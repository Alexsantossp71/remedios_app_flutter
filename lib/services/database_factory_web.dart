// Web-specific database factory.
// On web, sqflite uses sqflite_common_ffi_web which wraps IndexedDB via WASM.

import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Web database factory instance.
/// Use this factory directly when opening databases on web.
final databaseFactoryWeb = databaseFactoryFfiWeb;

/// No-op initialization for web (kept for compatibility).
void initializeDatabaseFactory() {
  // No initialization needed - databaseFactoryFfiWeb is ready to use
}
