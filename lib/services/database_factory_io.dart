// Mobile/Desktop database factory.
// On Android/iOS sqflite uses native SQLite.
// On desktop it could use sqflite_common_ffi but we'll use standard sqflite.

import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Compile-time stub for [databaseFactoryWeb] (only defined on web).
/// Never used at runtime: access is guarded by `kIsWeb`.
final databaseFactoryWeb = databaseFactory;

/// Initialize database factory per platform.
/// Android/iOS use sqflite's native implementation; desktop (Windows/Linux)
/// uses sqflite_common_ffi, since sqflite has no native desktop plugin.
void initializeDatabaseFactory() {
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}
