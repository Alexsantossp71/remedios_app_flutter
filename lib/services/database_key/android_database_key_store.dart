import 'package:flutter/services.dart';

import 'database_key_store.dart';

/// Android implementation of [DatabaseKeyStore] backed by the Android Keystore.
///
/// The 256-bit DEK is generated with a CSPRNG in Dart, sent once over the
/// platform channel and wrapped by a non-exportable AES-256-GCM Keystore key.
/// Only the wrapped envelope is persisted (noBackupFilesDir); the raw DEK
/// never reaches disk or logs. The channel implementation serializes
/// concurrent calls with an exclusive file lock (see
/// `AndroidDatabaseKeyStore.kt`).
class AndroidDatabaseKeyStore implements DatabaseKeyStore {
  AndroidDatabaseKeyStore({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('remedios_app/database_key_store');

  final MethodChannel _channel;

  @override
  Future<List<int>?> readKey() async {
    try {
      final String? hex = await _channel.invokeMethod<String>('readKey');
      if (hex == null) return null;
      return _decodeHex(hex);
    } on PlatformException catch (error) {
      throw DatabaseKeyRecoveryRequiredException(
        error.message ?? 'Falha ao recuperar a chave do banco no Keystore.',
      );
    } on MissingPluginException {
      throw const DatabaseKeyRecoveryRequiredException(
        'O cofre de chaves Android não está disponível nesta build.',
      );
    }
  }

  @override
  Future<bool> createKeyIfAbsent(List<int> key) async {
    if (key.length != 32) {
      throw ArgumentError('Database key must contain exactly 32 bytes.');
    }
    try {
      final created = await _channel.invokeMethod<bool>('createKeyIfAbsent', {
        'keyHex': _encodeHex(key),
      });
      return created ?? false;
    } on PlatformException catch (error) {
      throw DatabaseKeyRecoveryRequiredException(
        error.message ?? 'Falha ao proteger a chave do banco no Keystore.',
      );
    } on MissingPluginException {
      throw const DatabaseKeyRecoveryRequiredException(
        'O cofre de chaves Android não está disponível nesta build.',
      );
    }
  }

  @override
  Future<void> deleteKey() async {
    await _channel.invokeMethod<void>('deleteKey');
  }

  /// Restores a DEK recovered from a recovery envelope into the Keystore
  /// wrapper. Only used by the explicit recovery flow; never overwrites an
  /// intact key store.
  Future<void> restoreRecoveredKey(List<int> key) async {
    if (key.length != 32) {
      throw ArgumentError('Database key must contain exactly 32 bytes.');
    }
    await _channel.invokeMethod<void>('createKeyIfAbsent', {
      'keyHex': _encodeHex(key),
    });
  }

  String _encodeHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  List<int> _decodeHex(String hex) {
    if (hex.length != 64) {
      throw const DatabaseKeyRecoveryRequiredException(
        'A chave recuperada tem comprimento inválido.',
      );
    }
    return List<int>.generate(64 ~/ 2, (i) {
      final byte = int.tryParse(hex.substring(i * 2, i * 2 + 2), radix: 16);
      if (byte == null) {
        throw const DatabaseKeyRecoveryRequiredException(
          'A chave recuperada tem formato inválido.',
        );
      }
      return byte;
    });
  }
}
