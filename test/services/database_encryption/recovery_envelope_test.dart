import 'dart:convert';

import 'package:cryptography/cryptography.dart'
    show SecretBoxAuthenticationError;
import 'package:flutter_test/flutter_test.dart';
import 'package:remedios_app_flutter/services/database_key/recovery_envelope.dart';

const _password = 'recuperacao-segura-2026';

void main() {
  group('RecoveryEnvelope — criação e desbloqueio', () {
    test(
      'roundtrip correto: cria, codifica, decodifica e desbloqueia',
      () async {
        final key = List<int>.generate(32, (i) => i * 7 % 256);
        final envelope = await RecoveryEnvelope.create(
          databaseKey: key,
          recoveryPassword: _password,
        );

        final json = envelope.encode();
        final decoded = RecoveryEnvelope.decode(json);
        final unlocked = await decoded.unlock(recoveryPassword: _password);

        expect(unlocked, key);
        expect(decoded.version, RecoveryEnvelope.currentVersion);
        expect(decoded.kdf, 'pbkdf2-hmac-sha256');
        expect(decoded.iterations, RecoveryEnvelope.defaultIterations);
      },
    );

    test('formato JSON contém apenas campos públicos (ciphertext)', () async {
      final envelope = await RecoveryEnvelope.create(
        databaseKey: List<int>.generate(32, (_) => 42),
        recoveryPassword: _password,
      );
      final json = envelope.toJson();
      expect(
        json.keys,
        containsAll([
          'version',
          'kdf',
          'iterations',
          'salt',
          'nonce',
          'ciphertext',
          'mac',
        ]),
      );
      // O JSON nunca contém a chave em texto claro ou base64 direto.
      final encoded = jsonEncode(json);
      expect(encoded, isNot(contains('databaseKey')));
    });
  });

  group('RecoveryEnvelope — senhas incorretas', () {
    test('senha incorreta falha na autenticação e não retorna dados', () async {
      final envelope = await RecoveryEnvelope.create(
        databaseKey: List<int>.generate(32, (_) => 1),
        recoveryPassword: _password,
      );
      expect(
        () => envelope.unlock(recoveryPassword: 'senha-totalmente-errada!'),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });
  });

  group('RecoveryEnvelope — adulteração', () {
    test('mac adulterado falha a autenticação', () async {
      final envelope = await RecoveryEnvelope.create(
        databaseKey: List<int>.generate(32, (_) => 2),
        recoveryPassword: _password,
      );
      final tampered = Map<String, Object?>.from(envelope.toJson());
      final mac = base64Decode(tampered['mac']! as String);
      mac[0] = mac[0] ^ 0xFF;
      tampered['mac'] = base64Encode(mac);

      final decoded = RecoveryEnvelope.fromJson(tampered);
      expect(
        () => decoded.unlock(recoveryPassword: _password),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('ciphertext adulterado falha a autenticação', () async {
      final envelope = await RecoveryEnvelope.create(
        databaseKey: List<int>.generate(32, (_) => 3),
        recoveryPassword: _password,
      );
      final tampered = Map<String, Object?>.from(envelope.toJson());
      final ciphertext = base64Decode(tampered['ciphertext']! as String);
      ciphertext[5] = ciphertext[5] ^ 0x01;
      tampered['ciphertext'] = base64Encode(ciphertext);

      final decoded = RecoveryEnvelope.fromJson(tampered);
      expect(
        () => decoded.unlock(recoveryPassword: _password),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('iterações adulteradas para fora dos limites falham', () async {
      final envelope = await RecoveryEnvelope.create(
        databaseKey: List<int>.generate(32, (_) => 4),
        recoveryPassword: _password,
      );
      final tampered = Map<String, Object?>.from(envelope.toJson());
      tampered['iterations'] = 1; // abaixo do mínimo
      expect(
        () => RecoveryEnvelope.fromJson(tampered),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('RecoveryEnvelope — versionamento e compatibilidade', () {
    test('versão desconhecida é rejeitada com FormatException', () {
      expect(
        () => RecoveryEnvelope.fromJson({
          'version': 999,
          'kdf': 'pbkdf2-hmac-sha256',
          'iterations': 310000,
          'salt': base64Encode(List.filled(16, 0)),
          'nonce': base64Encode(List.filled(12, 0)),
          'ciphertext': base64Encode(List.filled(32, 0)),
          'mac': base64Encode(List.filled(16, 0)),
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('kdf desconhecido é rejeitado', () async {
      final envelope = await RecoveryEnvelope.create(
        databaseKey: List<int>.generate(32, (_) => 5),
        recoveryPassword: _password,
      );
      final tampered = Map<String, Object?>.from(envelope.toJson());
      tampered['kdf'] = 'argon2id';
      expect(
        () => RecoveryEnvelope.fromJson(tampered),
        throwsA(isA<FormatException>()),
      );
    });

    test('envelope malformado (JSON inválido) é rejeitado', () {
      expect(
        () => RecoveryEnvelope.decode('isto não é json'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => RecoveryEnvelope.decode('[1,2,3]'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('RecoveryEnvelope — validações de criação', () {
    test('chave com comprimento errado é rejeitada', () async {
      expect(
        () => RecoveryEnvelope.create(
          databaseKey: List<int>.filled(16, 0),
          recoveryPassword: _password,
        ),
        throwsArgumentError,
      );
    });

    test('senha curta é rejeitada', () async {
      expect(
        () => RecoveryEnvelope.create(
          databaseKey: List<int>.generate(32, (_) => 6),
          recoveryPassword: 'curta',
        ),
        throwsArgumentError,
      );
    });
  });
}
