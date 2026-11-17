/// Contract for storing the database's 256-bit data-encryption key.
///
/// Implementations must use an OS-backed secure store on native platforms.
/// The Web implementation must define its recovery and origin-loss behavior.
/// Implementations must never log keys or silently replace a missing key.
abstract interface class DatabaseKeyStore {
  /// Returns a defensive copy of the stored key, or null when no key exists.
  Future<List<int>?> readKey();

  /// Stores [key] only when no key exists and returns whether it was created.
  ///
  /// Implementations must make this operation atomic across concurrent calls.
  /// An existing key must never be overwritten by first-use initialization.
  /// [key] must contain exactly 32 bytes. Key rotation is a separate operation
  /// and is deliberately not part of this first-use contract.
  Future<bool> createKeyIfAbsent(List<int> key);

  /// Deletes the key only as part of an explicit, recoverable data lifecycle.
  /// Callers must first ensure the database is no longer needed or has been
  /// securely backed up.
  Future<void> deleteKey();
}
