import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Criptografa backups exportáveis sem armazenar a senha ou a chave no app.
///
/// Formato autenticado: AES-256-GCM + PBKDF2-HMAC-SHA256. A senha nunca é
/// persistida. Perder a senha significa perder a possibilidade de abrir o
/// arquivo; não existe recuperação ou envio da senha a um servidor.
class BackupCryptoService {
  BackupCryptoService._();

  static final BackupCryptoService instance = BackupCryptoService._();

  static const String encryptedMarker = 'remedios-app-encrypted-backup';
  static const int envelopeVersion = 1;
  static const int _iterations = 310000;
  static const String _aad = 'remedios-app-backup-envelope-v1';

  static final Pbkdf2 _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _iterations,
    bits: 256,
  );

  final AesGcm _cipher = AesGcm.with256bits();

  bool isEncrypted(Map<String, dynamic> value) =>
      value['app'] == encryptedMarker;

  /// Retorna um envelope JSON que não revela tabelas, nomes ou dados clínicos.
  Future<Map<String, dynamic>> encrypt(
    Map<String, dynamic> backup,
    String password,
  ) async {
    _validatePassword(password);
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final nonce = List<int>.generate(12, (_) => random.nextInt(256));
    final key = await _kdf.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    final plaintext = utf8.encode(jsonEncode(backup));
    final box = await _cipher.encrypt(
      plaintext,
      secretKey: key,
      nonce: nonce,
      aad: utf8.encode(_aad),
    );

    return {
      'app': encryptedMarker,
      'envelopeVersion': envelopeVersion,
      'algorithm': 'AES-256-GCM',
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iterations': _iterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    };
  }

  /// Autentica e descriptografa o envelope antes de qualquer alteração no DB.
  Future<Map<String, dynamic>> decrypt(
    Map<String, dynamic> envelope,
    String password,
  ) async {
    if (!isEncrypted(envelope) ||
        envelope['envelopeVersion'] != envelopeVersion ||
        envelope['algorithm'] != 'AES-256-GCM' ||
        envelope['kdf'] != 'PBKDF2-HMAC-SHA256' ||
        envelope['iterations'] != _iterations) {
      throw const BackupCryptoException(
        'Formato de backup criptografado não reconhecido.',
      );
    }

    try {
      final salt = _decodeField(envelope, 'salt', expectedLength: 16);
      final nonce = _decodeField(envelope, 'nonce', expectedLength: 12);
      final mac = _decodeField(envelope, 'mac', expectedLength: 16);
      final ciphertext = _decodeField(envelope, 'ciphertext');
      if (ciphertext.isEmpty) {
        throw const FormatException('Conteúdo vazio');
      }

      final key = await _kdf.deriveKeyFromPassword(
        password: password,
        nonce: salt,
      );
      final plaintext = await _cipher.decrypt(
        SecretBox(ciphertext, nonce: nonce, mac: Mac(mac)),
        secretKey: key,
        aad: utf8.encode(_aad),
      );
      final decoded = jsonDecode(utf8.decode(plaintext));
      if (decoded is! Map<String, dynamic> ||
          decoded['app'] != 'remedios-app') {
        throw const FormatException('Backup interno inválido');
      }
      return decoded;
    } on BackupCryptoException {
      rethrow;
    } catch (_) {
      throw const BackupCryptoException(
        'Senha incorreta ou arquivo danificado. Nenhum dado foi alterado.',
      );
    }
  }

  List<int> _decodeField(
    Map<String, dynamic> envelope,
    String field, {
    int? expectedLength,
  }) {
    final value = envelope[field];
    if (value is! String || value.isEmpty) {
      throw const FormatException('Campo criptográfico ausente');
    }
    final bytes = base64Decode(value);
    if (expectedLength != null && bytes.length != expectedLength) {
      throw const FormatException('Tamanho criptográfico inválido');
    }
    return bytes;
  }

  void _validatePassword(String password) {
    if (password.length < 6) {
      throw const BackupCryptoException(
        'Use uma senha com pelo menos 6 caracteres.',
      );
    }
  }
}

class BackupCryptoException implements Exception {
  const BackupCryptoException(this.message);

  final String message;

  @override
  String toString() => message;
}
