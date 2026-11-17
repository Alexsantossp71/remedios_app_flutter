/// Contract for storing the database's 256-bit data-encryption key.
///
/// Implementations must use an OS-backed secure store on native platforms.
/// The Web implementation must define its recovery and origin-loss behavior.
/// Implementations must never log keys or silently replace a missing key.
abstract interface class DatabaseKeyStore {
  /// Returns a defensive copy of the stored key, or null when no key exists.
  Future<List<int>?> readKey();

  /// Persists exactly 32 bytes, replacing the existing key atomically.
  Future<void> writeKey(List<int> key);

  /// Deletes the stored key. Callers must first ensure the database is no
  /// longer needed or has been securely backed up.
  Future<void> deleteKey();
}
