import 'dart:convert';

import 'package:database_key_recovery_poc/recovery_envelope.dart';
import 'package:test/test.dart';

void main() {
  const password = 'a-long-test-recovery-passphrase';
  final databaseKey = List<int>.generate(32, (index) => index + 1);

  group('RecoveryEnvelope', () {
    test('round-trips a key through JSON and unlock', () async {
      final envelope = await RecoveryEnvelope.create(
        databaseKey: databaseKey,
        recoveryPassword: password,
        iterations: RecoveryEnvelope.minimumIterations,
      );
      final decoded = RecoveryEnvelope.fromJson(
        jsonDecode(jsonEncode(envelope.toJson())) as Map<String, Object?>,
      );

      expect(await decoded.unlock(recoveryPassword: password), databaseKey);
    });

    test('uses fresh salt and nonce for every envelope', () async {
      final first = await RecoveryEnvelope.create(
        databaseKey: databaseKey,
        recoveryPassword: password,
        iterations: RecoveryEnvelope.minimumIterations,
      );
      final second = await RecoveryEnvelope.create(
        databaseKey: databaseKey,
        recoveryPassword: password,
        iterations: RecoveryEnvelope.minimumIterations,
      );

      expect(first.salt, isNot(equals(second.salt)));
      expect(first.nonce, isNot(equals(second.nonce)));
    });

    test('rejects an incorrect recovery password', () async {
      final envelope = await RecoveryEnvelope.create(
        databaseKey: databaseKey,
        recoveryPassword: password,
        iterations: RecoveryEnvelope.minimumIterations,
      );

      await expectLater(
        envelope.unlock(recoveryPassword: 'another-wrong-password'),
        throwsA(anything),
      );
    });

    test('rejects modified ciphertext', () async {
      final envelope = await RecoveryEnvelope.create(
        databaseKey: databaseKey,
        recoveryPassword: password,
        iterations: RecoveryEnvelope.minimumIterations,
      );
      final json = envelope.toJson();
      final ciphertext = base64Decode(json['ciphertext']! as String);
      ciphertext[0] ^= 1;
      json['ciphertext'] = base64Encode(ciphertext);
      final modified = RecoveryEnvelope.fromJson(json);

      await expectLater(
        modified.unlock(recoveryPassword: password),
        throwsA(anything),
      );
    });

    test('rejects unsupported versions and unsafe KDF costs', () {
      expect(
        () => RecoveryEnvelope.fromJson({
          'version': 99,
          'kdf': 'pbkdf2-hmac-sha256',
          'iterations': RecoveryEnvelope.minimumIterations,
          'salt': base64Encode(List<int>.filled(16, 1)),
          'nonce': base64Encode(List<int>.filled(12, 2)),
          'ciphertext': base64Encode(List<int>.filled(32, 3)),
          'mac': base64Encode(List<int>.filled(16, 4)),
        }),
        throwsFormatException,
      );
      expect(
        () => RecoveryEnvelope.fromJson({
          'version': 1,
          'kdf': 'pbkdf2-hmac-sha256',
          'iterations': 1,
          'salt': base64Encode(List<int>.filled(16, 1)),
          'nonce': base64Encode(List<int>.filled(12, 2)),
          'ciphertext': base64Encode(List<int>.filled(32, 3)),
          'mac': base64Encode(List<int>.filled(16, 4)),
        }),
        throwsFormatException,
      );
    });

    test('rejects keys not exactly 32 bytes and weak passwords', () async {
      expect(
        () => RecoveryEnvelope.create(
          databaseKey: [1, 2, 3],
          recoveryPassword: password,
        ),
        throwsArgumentError,
      );
      expect(
        () => RecoveryEnvelope.create(
          databaseKey: databaseKey,
          recoveryPassword: 'too-short',
        ),
        throwsArgumentError,
      );
    });
  });
}
