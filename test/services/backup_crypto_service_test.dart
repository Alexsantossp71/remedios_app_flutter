import 'package:flutter_test/flutter_test.dart';
import 'package:remedios_app_flutter/services/backup_crypto_service.dart';

void main() {
  group('BackupCryptoService', () {
    const backup = <String, dynamic>{
      'app': 'remedios-app',
      'formatVersion': 1,
      'schemaVersion': 11,
      'tables': {
        'treatments': [
          {'id': 'fake-1', 'name': 'Medicamento de teste'},
        ],
      },
    };

    test('criptografa e restaura sem expor dados no envelope', () async {
      final service = BackupCryptoService.instance;
      final encrypted = await service.encrypt(
        backup,
        'senha-forte-de-teste-123',
      );

      expect(service.isEncrypted(encrypted), isTrue);
      expect(encrypted.toString(), isNot(contains('Medicamento de teste')));
      expect(encrypted.toString(), isNot(contains('fake-1')));

      final restored = await service.decrypt(
        encrypted,
        'senha-forte-de-teste-123',
      );
      expect(restored, backup);
    });

    test('usa salt e nonce diferentes em cada exportação', () async {
      final service = BackupCryptoService.instance;
      final first = await service.encrypt(backup, 'senha-forte-de-teste-123');
      final second = await service.encrypt(backup, 'senha-forte-de-teste-123');

      expect(first['salt'], isNot(second['salt']));
      expect(first['nonce'], isNot(second['nonce']));
    });

    test('senha incorreta é rejeitada sem retornar conteúdo', () async {
      final service = BackupCryptoService.instance;
      final encrypted = await service.encrypt(
        backup,
        'senha-forte-de-teste-123',
      );

      await expectLater(
        service.decrypt(encrypted, 'senha-errada-123'),
        throwsA(isA<BackupCryptoException>()),
      );
    });

    test('alteração no ciphertext falha na autenticação', () async {
      final service = BackupCryptoService.instance;
      final encrypted = await service.encrypt(
        backup,
        'senha-forte-de-teste-123',
      );
      final tampered = Map<String, dynamic>.from(encrypted);
      final bytes = tampered['ciphertext'] as String;
      tampered['ciphertext'] = '${bytes.substring(0, bytes.length - 4)}AAAA';

      await expectLater(
        service.decrypt(tampered, 'senha-forte-de-teste-123'),
        throwsA(isA<BackupCryptoException>()),
      );
    });

    test('rejeita senha curta', () async {
      await expectLater(
        BackupCryptoService.instance.encrypt(backup, 'curta'),
        throwsA(isA<BackupCryptoException>()),
      );
    });
  });
}
