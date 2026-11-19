import 'dart:math';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;

import 'database_key_store.dart';
import 'in_memory_database_key_store.dart';
import 'native_database_key_store.dart';
import 'web_database_key_store.dart';

/// Facade that resolves the database key for the current platform.
///
/// - Android: the DEK is created once with a CSPRNG and wrapped by the
///   Android Keystore (via the `remedios_app/database_key_store` channel).
///   Subsequent launches unwrap it transparently; a broken envelope throws
///   [DatabaseKeyRecoveryRequiredException] and never creates a new key.
/// - iOS / macOS: the DEK is wrapped by a non-exportable AES-256 key stored
///   in the platform Keychain (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly).
///   Implemented in `ios/Runner/Security/IosDatabaseKeyStore.swift` and
///   `macos/Runner/Security/MacosDatabaseKeyStore.swift`; the Dart side uses
///   the same `AndroidDatabaseKeyStore` channel contract (renamed conceptually
///   to `NativeDatabaseKeyStore`) so the same MethodChannel works on every
///   native platform. See ADR 0009 for the full design and validation status.
/// - Web: the key is resolved through the explicit unlock flow
///   ([WebDatabaseKeyStore]); sessions start locked until the user unlocks.
/// - Tests: an [InMemoryDatabaseKeyStore] (or any injected store) is used.
class DatabaseKeyService {
  DatabaseKeyService._({
    DatabaseKeyStore? injectedStore,
    WebDatabaseKeyStore? injectedWebStore,
  }) : _injectedStore = injectedStore {
    if (kIsWeb) {
      _webStore = injectedWebStore ?? WebDatabaseKeyStore();
    } else if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      // Android, iOS and macOS share the `remedios_app/database_key_store`
      // channel contract. The native host (Kotlin on Android, Swift on iOS
      // and macOS) implements readKey / createKeyIfAbsent / deleteKey.
      _nativeStore = injectedStore ?? NativeDatabaseKeyStore();
    } else {
      // Windows and Linux are still out of scope (no OS keychain abstraction
      // implemented yet); tests and tooling may inject an in-memory store.
      _nativeStore = injectedStore;
    }
  }

  static DatabaseKeyService? _instance;

  /// Test-only override: the next access to [instance] returns this.
  @visibleForTesting
  static DatabaseKeyService? instanceOverride;

  static DatabaseKeyService get instance =>
      instanceOverride ?? (_instance ??= DatabaseKeyService._());

  /// Test-only: rebuilds the singleton bound to injected stores.
  @visibleForTesting
  static void resetInstanceForTesting({
    DatabaseKeyStore? store,
    WebDatabaseKeyStore? webStore,
  }) {
    _instance = DatabaseKeyService._(
      injectedStore: store ?? InMemoryDatabaseKeyStore(),
      injectedWebStore: webStore,
    );
    instanceOverride = _instance;
  }

  DatabaseKeyStore? _nativeStore;
  WebDatabaseKeyStore? _webStore;
  final DatabaseKeyStore? _injectedStore;

  /// Resolves the key on native platforms, creating it on first use.
  ///
  /// Returns null only when the secure store has no key at all. A missing key
  /// alongside an existing database must be handled by the caller
  /// (migration/recovery), never by silently creating a new key over data.
  Future<List<int>?> resolveOrCreateKey() async {
    if (kIsWeb) {
      return _webStore!.readKey();
    }
    final store = _nativeStore;
    if (store == null) {
      throw UnsupportedError(
        'No database key store available for this platform in this delivery '
        '(scope: Android, iOS, macOS and Web). Windows and Linux remain on '
        'legacy plaintext until a key-store abstraction is implemented.',
      );
    }
    final existing = await store.readKey();
    if (existing != null) {
      return existing;
    }
    final random = Random.secure();
    final key = List<int>.generate(32, (_) => random.nextInt(256));
    final created = await store.createKeyIfAbsent(key);
    if (!created) {
      // A concurrent flow created the key first: read the stored one.
      final nowExisting = await store.readKey();
      if (nowExisting == null) {
        throw const DatabaseKeyRecoveryRequiredException(
          'A chave do banco existe mas não pôde ser recuperada.',
        );
      }
      return nowExisting;
    }
    return key;
  }

  /// Resolves the current session key or signals that explicit unlock is
  /// required (web). On native this delegates to [resolveOrCreateKey].
  Future<List<int>?> resolveKeyForOpen() async {
    if (kIsWeb) {
      return _webStore!.readKey();
    }
    return resolveOrCreateKey();
  }

  // ---- Flows used by the unlock gate (web) and recovery UI ----

  /// Web state of the key lifecycle.
  DatabaseKeyState get webState {
    assert(kIsWeb, 'webState is only meaningful on web');
    return _webStore?.state ?? DatabaseKeyState.needsSetup;
  }

  /// Web first use: creates the DEK and its recovery envelope.
  Future<List<int>> setupWithPassword(String password) {
    assert(kIsWeb);
    return _webStore!.setupWithPassword(password);
  }

  /// Web explicit unlock for this session.
  Future<List<int>> unlockWithPassword(String password) {
    assert(kIsWeb);
    return _webStore!.unlockWithPassword(password);
  }

  /// Web clean-profile restoration from an exported envelope.
  Future<List<int>> restoreEnvelope(String envelopeJson, String password) {
    assert(kIsWeb);
    return _webStore!.restoreEnvelope(envelopeJson, password);
  }

  /// Web: exported recovery envelope JSON (ciphertext only), or null.
  String? exportEnvelopeJson() {
    assert(kIsWeb);
    return _webStore?.exportEnvelopeJson();
  }

  /// Native (Android/iOS/macOS) recovery flow: stores a DEK recovered from a
  /// recovery envelope into the OS-backed key store without overwriting a
  /// valid key.
  Future<void> restoreRecoveredKeyOnNative(List<int> key) async {
    assert(!kIsWeb);
    final store = _nativeStore ?? _injectedStore;
    if (store == null) {
      throw UnsupportedError('No key store available for restoration.');
    }
    await store.createKeyIfAbsent(key);
  }
}
