/// Contract for storing the local database's 256-bit data-encryption key
/// (DEK).
///
/// Implementations must use an OS-backed secure store on native platforms
/// (Android Keystore via the app's platform channel) and an explicit
/// password-unlock + authenticated recovery envelope on the Web. Implementations
/// must never log keys, never persist the key in plaintext and never silently
/// replace a missing key.
abstract interface class DatabaseKeyStore {
  /// Returns a defensive copy of the stored DEK, or null when no key exists.
  ///
  /// May throw [DatabaseKeyRecoveryRequiredException] when the stored material
  /// is incomplete or fails authentication. Callers must not create a new
  /// database in that case.
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

/// Thrown when the database key cannot be recovered and user intervention
/// (restoring a recovery envelope) is required.
///
/// Receiving this exception must NEVER lead to recreating an empty database:
/// the original database file remains untouched on disk.
class DatabaseKeyRecoveryRequiredException implements Exception {
  const DatabaseKeyRecoveryRequiredException(this.message);

  final String message;

  @override
  String toString() => 'DatabaseKeyRecoveryRequiredException: $message';
}

/// Thrown on the Web when the database key exists (a recovery envelope is
/// stored) but the user has not unlocked this session yet.
///
/// The UI must present the explicit unlock flow and call
/// [DatabaseKeyService.unlockWithPassword]; the database must not be opened
/// until then.
class DatabaseUnlockRequiredException implements Exception {
  const DatabaseUnlockRequiredException(this.message);

  final String message;

  @override
  String toString() => 'DatabaseUnlockRequiredException: $message';
}

/// Thrown when the user-provided recovery password does not authenticate the
/// stored recovery envelope.
class DatabaseUnlockWrongPasswordException implements Exception {
  const DatabaseUnlockWrongPasswordException(this.message);

  final String message;

  @override
  String toString() => 'DatabaseUnlockWrongPasswordException: $message';
}

/// States of the key lifecycle surfaced to the application UI.
enum DatabaseKeyState {
  /// A key exists and was resolved for the current session.
  unlocked,

  /// A key exists (an envelope is stored) but requires explicit unlock.
  locked,

  /// No key exists yet (fresh install on web, or nothing to protect).
  needsSetup,

  /// Stored key material is incomplete or fails authentication; recovery is
  /// required and must not fall back to creating an empty database.
  recoveryRequired,
}
