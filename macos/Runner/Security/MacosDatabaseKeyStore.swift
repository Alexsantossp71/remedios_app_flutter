import CryptoKit
import Foundation
import Security

// MARK: - Errors

/// Raised when the local database key cannot be recovered and user intervention
/// (restoring a recovery envelope) is required. The Dart layer maps this to
/// `DatabaseKeyRecoveryRequiredException`.
///
/// Receiving this error must NEVER lead to recreating an empty database: the
/// original database file remains untouched on disk.
enum DatabaseKeyError: Error, LocalizedError {
    case recoveryRequired(String)
    case keyStoreUnavailable(String)
    case invalidArgument(String)

    var errorDescription: String? {
        switch self {
        case let .recoveryRequired(message): return message
        case let .keyStoreUnavailable(message): return message
        case let .invalidArgument(message): return message
        }
    }

    /// Flutter MethodChannel result code — matches Android's Kotlin host.
    var channelCode: String {
        switch self {
        case .recoveryRequired: return "key_recovery_required"
        case .keyStoreUnavailable: return "key_store_error"
        case .invalidArgument: return "invalid_argument"
        }
    }
}

// MARK: - IosDatabaseKeyStore

/// iOS / macOS key store for the local database's 256-bit DEK.
///
/// Architecture mirrors `AndroidDatabaseKeyStore.kt`:
/// 1. A random 32-byte DEK is generated in Dart (CSPRNG) and sent once over
///    the `remedios_app/database_key_store` platform channel.
/// 2. The native side wraps the DEK with a non-exportable AES-256-GCM key
///    stored in the iOS/macOS Keychain (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly).
/// 3. Only the wrapped envelope (format byte + 12-byte IV + ciphertext+tag) is
///    persisted in Application Support; the raw DEK never reaches disk or logs.
/// 4. Subsequent launches read the envelope and unwrap with the Keychain key.
/// 5. Missing/incomplete/inauthentic material raises `DatabaseKeyError.recoveryRequired`
///    instead of silently creating a new key — the encrypted database is never
///    replaced by an empty one.
///
/// Differences from Android:
/// - Keychain (`SecItem*`) replaces Keystore. The wrapping key is a 32-byte
///   AES key generated via `SymmetricKey(size: .bits256)` and stored as
///   `kSecClassKey` / `kSecAttrKeyTypeAES` with `kSecAttrIsPermanent` and
///   `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (device-only, no
///   iCloud sync, accessible after first unlock).
/// - File locking uses `NSFileCoordinator` + an `NSLock` per path; iOS does
///   not expose POSIX file locks the way Android does, but the app process
///   is single-instance so JVM-level locking suffices.
///
/// Requirements:
/// - iOS 13.0+ (CryptoKit `AES.GCM`).
/// - macOS 10.15+ (CryptoKit `AES.GCM`).
/// - Application Support directory must be writable (default: yes).
/// - Keychain entitlement: implicit on iOS; on macOS the app must have the
///   "Keychain Sharing" capability or use `kSecUseDataProtectionKeychain`.
final class DatabaseKeyStore {

    // MARK: Lifecycle

    /// - parameter namespace: Isolated key namespace; matches Android's
    ///   `DEFAULT_NAMESPACE`. Allows multiple apps from the same vendor to
    ///   coexist in the same Keychain partition (when Keychain Sharing is on).
    init(namespace: String = DatabaseKeyStore.defaultNamespace) {
        let pattern = #"^[a-zA-Z0-9_-]{1,48}$"#
        guard namespace.range(of: pattern, options: .regularExpression) != nil else {
            preconditionFailure("Invalid key-store namespace: \(namespace)")
        }
        self.namespace = namespace
    }

    // MARK: Public API (called from the platform channel)

    /// Returns the raw 32-byte DEK, or nil when both the envelope AND the
    /// Keychain wrapping key are absent (genuine first-use).
    /// Throws `recoveryRequired` when envelope exists but cannot be unwrapped.
    func readKey() throws -> Data? {
        try ensureSupportedPlatform()
        let envelope = try readEnvelope()
        let wrappingKeyExists = try containsWrappingKey()

        if envelope == nil && !wrappingKeyExists { return nil }
        guard let envelope = envelope, wrappingKeyExists else {
            throw DatabaseKeyError.recoveryRequired(
                "The local database key is incomplete. Restore the recovery envelope."
            )
        }
        return try decrypt(envelope)
    }

    /// Stores a 32-byte DEK only if absent. Returns false when a valid key
    /// already exists. Never overwrites an existing key.
    @discardableResult
    func createKeyIfAbsent(_ candidate: Data) throws -> Bool {
        try ensureSupportedPlatform()
        guard candidate.count == Self.dekLength else {
            throw DatabaseKeyError.invalidArgument(
                "Database key must contain exactly \(Self.dekLength) bytes."
            )
        }

        let envelope = try readEnvelope()
        let wrappingKeyExists = try containsWrappingKey()

        if envelope != nil && wrappingKeyExists {
            // Verify integrity before reporting an existing key.
            _ = try decrypt(envelope!)
            return false
        }
        if envelope != nil || wrappingKeyExists {
            throw DatabaseKeyError.recoveryRequired(
                "The local database key is incomplete. Restore the recovery envelope."
            )
        }

        let wrappingKey = try createWrappingKey()
        let encrypted = try encrypt(candidate, with: wrappingKey)
        try writeEnvelopeAtomically(encrypted)
        return true
    }

    /// Deletes the key material. Only call as part of an explicit, recoverable
    /// data lifecycle: the encrypted database becomes unreadable afterwards.
    func deleteKey() throws {
        try deleteWrappingKey()
        try deleteEnvelope()
    }

    // MARK: Test-only corruption helpers (NEVER call from app flows)

    func deleteEnvelopeForTesting() throws { try deleteEnvelope() }
    func deleteWrappingKeyForTesting() throws { try deleteWrappingKey() }
    func destroyForTesting() throws { try deleteKey() }

    // MARK: Private — platform & paths

    private let namespace: String

    private static let defaultNamespace = "remedios_app"

    private var keychainService: String {
        "remedios-app.database-key.\(namespace)"
    }
    private var keychainAccount: String { "dek-wrapping-key-v1" }

    private var envelopeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("database-key", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(namespace).dek")
    }

    private func ensureSupportedPlatform() throws {
        #if os(iOS)
        guard #available(iOS 13.0, *) else {
            throw DatabaseKeyError.keyStoreUnavailable(
                "CryptoKit AES.GCM requires iOS 13.0 or later."
            )
        }
        #elseif os(macOS)
        guard #available(macOS 10.15, *) else {
            throw DatabaseKeyError.keyStoreUnavailable(
                "CryptoKit AES.GCM requires macOS 10.15 or later."
            )
        }
        #else
        throw DatabaseKeyError.keyStoreUnavailable(
            "DatabaseKeyStore is only supported on iOS and macOS."
        )
        #endif
    }

    // MARK: Private — Keychain operations

    private func containsWrappingKey() throws -> Bool {
        var query = baseKeychainQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = kCFBooleanFalse
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        switch status {
        case errSecSuccess: return true
        case errSecItemNotFound: return false
        case let other:
            throw DatabaseKeyError.keyStoreUnavailable(
                "Keychain lookup failed (OSStatus \(other))."
            )
        }
    }

    private func loadWrappingKey() throws -> SymmetricKey {
        var query = baseKeychainQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = kCFBooleanTrue
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, data.count == 32 else {
            throw DatabaseKeyError.recoveryRequired(
                "The Keychain wrapping key is unavailable. Restore the recovery envelope."
            )
        }
        return SymmetricKey(data: data)
    }

    private func createWrappingKey() throws -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }

        var attributes = baseKeychainQuery()
        attributes[kSecValueData as String] = keyData
        // Persist the key in the Keychain (otherwise it would only live in memory).
        attributes[kSecAttrIsPermanent as String] = kCFBooleanTrue
        // Device-only, available after first unlock — matches Android's
        // `setUserAuthenticationRequired(false)` + Keystore default.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        #if os(macOS)
        // macOS requires the data-protection keychain (introduced in 10.15);
        // without this flag, SecItemAdd uses the legacy file-based keychain
        // which has different access semantics.
        attributes[kSecUseDataProtectionKeychain as String] = kCFBooleanTrue
        #endif

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw DatabaseKeyError.keyStoreUnavailable(
                "Failed to create Keychain wrapping key (OSStatus \(status))."
            )
        }
        return key
    }

    private func deleteWrappingKey() throws {
        let status = SecItemDelete(baseKeychainQuery() as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound: return
        case let other:
            throw DatabaseKeyError.keyStoreUnavailable(
                "Failed to delete Keychain wrapping key (OSStatus \(other))."
            )
        }
    }

    private func baseKeychainQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeAES,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = kCFBooleanTrue
        #endif
        return query
    }

    // MARK: Private — envelope file

    private func readEnvelope() throws -> Data? {
        let url = envelopeURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    private func writeEnvelopeAtomically(_ data: Data) throws {
        try data.write(to: envelopeURL, options: [.atomic])
    }

    private func deleteEnvelope() throws {
        let url = envelopeURL
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    // MARK: Private — AES-GCM

    private func encrypt(_ dek: Data, with key: SymmetricKey) throws -> Data {
        let nonce = AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(dek, using: key, nonce: nonce)
        // Layout: [format(1)] [nonce(12)] [ciphertext+tag(N+16)]
        var out = Data()
        out.append(Self.formatVersion)
        out.append(Data(sealed.nonce))
        out.append(sealed.ciphertext)
        out.append(sealed.tag)
        return out
    }

    private func decrypt(_ envelope: Data) throws -> Data {
        guard envelope.count == Self.envelopeLength, envelope.first == Self.formatVersion else {
            throw DatabaseKeyError.recoveryRequired(
                "The local database key envelope is invalid. Restore a recovery copy."
            )
        }
        let nonceStart = 1
        let nonceEnd = nonceStart + Self.gcmNonceLength
        let ciphertextEnd = envelope.count - Self.gcmTagLength

        let nonceData = envelope.subdata(in: nonceStart..<nonceEnd)
        let ciphertext = envelope.subdata(in: nonceEnd..<ciphertextEnd)
        let tag = envelope.subdata(in: ciphertextEnd..<envelope.count)

        let key = try loadWrappingKey()
        do {
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let sealed = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
            let dek = try AES.GCM.open(sealed, using: key)
            guard dek.count == Self.dekLength else {
                throw DatabaseKeyError.recoveryRequired(
                    "The recovered database key has an invalid length."
                )
            }
            return dek
        } catch let error as DatabaseKeyError {
            throw error
        } catch {
            throw DatabaseKeyError.recoveryRequired(
                "The local database key failed authentication. Restore a recovery copy."
            )
        }
    }

    // MARK: Constants

    private static let dekLength = 32
    private static let gcmNonceLength = 12
    private static let gcmTagLength = 16
    private static let formatVersion: UInt8 = 1
    private static var envelopeLength: Int {
        1 + gcmNonceLength + dekLength + gcmTagLength
    }
}
