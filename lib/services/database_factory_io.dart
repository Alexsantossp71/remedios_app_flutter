// Mobile/Desktop database factory.
// On Android/iOS sqflite uses native SQLite.
// On desktop it could use sqflite_common_ffi but we'll use standard sqflite.

/// Initialize database factory for mobile/desktop platforms.
/// No-op since sqflite handles this automatically per platform.
void initializeDatabaseFactory() {
  // No initialization needed - sqflite handles platform-specific setup
}
