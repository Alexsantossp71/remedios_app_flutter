import 'package:flutter/services.dart';

import 'android_database_key_store.dart';
import 'database_key_store.dart';

/// Native (Android + iOS + macOS) implementation of [DatabaseKeyStore] backed
/// by the platform's OS secure store (Android Keystore or Apple Keychain).
///
/// All three native platforms share the same `remedios_app/database_key_store`
/// MethodChannel protocol:
///
///   readKey()                       -> String? (hex, 64 chars) or null
///   createKeyIfAbsent(keyHex)       -> bool
///   deleteKey()                     -> void
///
/// Native hosts:
/// - Android: `android/app/src/main/kotlin/.../MainActivity.kt` delegates to
///   `AndroidDatabaseKeyStore.kt` (Android Keystore + AES-GCM).
/// - iOS: `ios/Runner/AppDelegate.swift` delegates to
///   `IosDatabaseKeyStore.swift` (Keychain + CryptoKit `AES.GCM`).
/// - macOS: `macos/Runner/MainFlutterWindow.swift` delegates to
///   `MacosDatabaseKeyStore.swift` (Keychain + CryptoKit `AES.GCM`).
///
/// The Dart-side protocol is identical on every native platform, so this
/// class is effectively a typed alias for [AndroidDatabaseKeyStore] that
/// documents the cross-platform contract. See ADR 0009 for the design and
/// validation status of the iOS/macOS expansion.
class NativeDatabaseKeyStore implements DatabaseKeyStore {
  NativeDatabaseKeyStore({MethodChannel? channel})
    : _delegate = AndroidDatabaseKeyStore(channel: channel);

  final AndroidDatabaseKeyStore _delegate;

  @override
  Future<List<int>?> readKey() => _delegate.readKey();

  @override
  Future<bool> createKeyIfAbsent(List<int> key) =>
      _delegate.createKeyIfAbsent(key);

  @override
  Future<void> deleteKey() => _delegate.deleteKey();

  /// Restores a DEK recovered from a recovery envelope into the OS-backed
  /// key store. Only used by the explicit recovery flow; never overwrites an
  /// intact key store.
  Future<void> restoreRecoveredKey(List<int> key) =>
      _delegate.restoreRecoveredKey(key);
}
