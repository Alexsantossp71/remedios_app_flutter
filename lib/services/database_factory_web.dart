// Web-specific database factory.
// On web, sqflite uses IndexedDB natively - no additional setup needed.

/// Initialize database factory for web platform.
/// No-op since sqflite on web uses IndexedDB by default.
void initializeDatabaseFactory() {
  // No initialization needed for web - uses IndexedDB automatically
}
