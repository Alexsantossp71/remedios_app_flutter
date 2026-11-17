import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Portable authenticated envelope for wrapping a random database key.
///
/// This is a cryptographic-format POC only. It does not store keys in an
/// operating-system vault, integrate with SQLite, or replace encrypted backups.
class RecoveryEnvelope {
  RecoveryEnvelope._({
    required this.version,
    required this.kdf,
    required this.iterations,
    required this.salt,
    required this.nonce,
    required this.ciphertext,
    required this.mac,
  });

  static const int currentVersion = 1;
  static const int defaultIterations = 310000;
  static const int minimumIterations = 100000;
  static const int maximumIterations = 2000000;
  static const int _saltLength = 16;
  static const int _nonceLength = 12;
  static const int _macLength = 16;

  final int version;
  final String kdf;
  final int iterations;
  final List<int> salt;
  final List<int> nonce;
  final List<int> ciphertext;
  final List<int> mac;

  static Future<RecoveryEnvelope> create({
    required List<int> databaseKey,
    required String recoveryPassword,
    int iterations = defaultIterations,
  }) async {
    if (databaseKey.length != 32) {
      throw ArgumentError('Database key must contain exactly 32 bytes.');
    }
    _validatePassword(recoveryPassword);
    _validateIterations(iterations);

    final random = Random.secure();
    final salt = List<int>.generate(_saltLength, (_) => random.nextInt(256));
    final nonce = List<int>.generate(_nonceLength, (_) => random.nextInt(256));
    final aad = _aad(iterations, salt);
    final wrappingKey = await _deriveKey(recoveryPassword, salt, iterations);
    final box = await AesGcm.with256bits().encrypt(
      databaseKey,
      secretKey: wrappingKey,
      nonce: nonce,
      aad: aad,
    );

    return RecoveryEnvelope._(
      version: currentVersion,
      kdf: 'pbkdf2-hmac-sha256',
      iterations: iterations,
      salt: salt,
      nonce: nonce,
      ciphertext: box.cipherText,
      mac: box.mac.bytes,
    );
  }

  Future<List<int>> unlock({required String recoveryPassword}) async {
    _validatePassword(recoveryPassword);
    if (version != currentVersion || kdf != 'pbkdf2-hmac-sha256') {
      throw const FormatException('Unsupported recovery envelope version or KDF.');
    }
    _validateIterations(iterations);
    if (salt.length != _saltLength ||
        nonce.length != _nonceLength ||
        mac.length != _macLength ||
        ciphertext.length != 32) {
      throw const FormatException('Invalid recovery envelope lengths.');
    }

    final wrappingKey =
        await _deriveKey(recoveryPassword, salt, iterations);
    final box = SecretBox(
      ciphertext,
      nonce: nonce,
      mac: Mac(mac),
    );
    return AesGcm.with256bits().decrypt(
      box,
      secretKey: wrappingKey,
      aad: _aad(iterations, salt),
    );
  }

  Map<String, Object> toJson() => {
        'version': version,
        'kdf': kdf,
        'iterations': iterations,
        'salt': base64Encode(salt),
        'nonce': base64Encode(nonce),
        'ciphertext': base64Encode(ciphertext),
        'mac': base64Encode(mac),
      };

  factory RecoveryEnvelope.fromJson(Map<String, Object?> json) {
    try {
      final envelope = RecoveryEnvelope._(
        version: json['version']! as int,
        kdf: json['kdf']! as String,
        iterations: json['iterations']! as int,
        salt: base64Decode(json['salt']! as String),
        nonce: base64Decode(json['nonce']! as String),
        ciphertext: base64Decode(json['ciphertext']! as String),
        mac: base64Decode(json['mac']! as String),
      );
      if (envelope.version != currentVersion ||
          envelope.kdf != 'pbkdf2-hmac-sha256') {
        throw const FormatException('Unsupported recovery envelope version or KDF.');
      }
      _validateIterations(envelope.iterations);
      if (envelope.salt.length != _saltLength ||
          envelope.nonce.length != _nonceLength ||
          envelope.ciphertext.length != 32 ||
          envelope.mac.length != _macLength) {
        throw const FormatException('Invalid recovery envelope lengths.');
      }
      return envelope;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Malformed recovery envelope.');
    }
  }

  static Future<SecretKey> _deriveKey(
    String password,
    List<int> salt,
    int iterations,
  ) {
    final kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    return kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
  }

  static List<int> _aad(int iterations, List<int> salt) => utf8.encode(
        'remedio-na-hora-db-key-envelope:v1:pbkdf2-hmac-sha256:'
        '$iterations:${base64Encode(salt)}',
      );

  static void _validatePassword(String password) {
    if (password.length < 12) {
      throw ArgumentError('Recovery password must contain at least 12 characters.');
    }
  }

  static void _validateIterations(int value) {
    if (value < minimumIterations || value > maximumIterations) {
      throw const FormatException('KDF iteration count is outside safe bounds.');
    }
  }
}
