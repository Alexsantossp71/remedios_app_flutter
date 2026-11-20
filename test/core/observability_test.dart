import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:remedios_app_flutter/core/observability.dart';

void main() {
  group('redactPii', () {
    test('redacta e-mail', () {
      expect(
        redactPii('contato de alex@exemplo.com para suporte'),
        contains('[REDACTED]'),
      );
      expect(
        redactPii('contato de alex@exemplo.com para suporte'),
        isNot(contains('alex@exemplo.com')),
      );
    });

    test('redacta CPF com e sem pontuação', () {
      expect(
        redactPii('CPF do paciente: 123.456.789-00'),
        contains('[REDACTED]'),
      );
      expect(
        redactPii('CPF do paciente: 12345678900'),
        isNot(contains('12345678900')),
      );
    });

    test('redacta telefone brasileiro com DDD', () {
      final redacted = redactPii('ligar para (11) 98888-7777 agora');
      expect(redacted, contains('[REDACTED]'));
      expect(redacted, isNot(contains('98888-7777')));
    });

    test('redacta cartão de 16 dígitos', () {
      expect(
        redactPii('cartão 4111 1111 1111 1111 válido'),
        contains('[REDACTED]'),
      );
    });

    test('preserva texto sem PII', () {
      const input = 'Falha ao abrir o banco de dados criptografado.';
      expect(redactPii(input), input);
    });
  });

  group('redactSentryEvent (beforeSend)', () {
    test('redacta PII da mensagem e preserva o resto', () {
      final event = SentryEvent(
        message: SentryMessage(
          'Erro ao salvar perfil alex@exemplo.com CPF 123.456.789-00',
        ),
      );
      final result = redactSentryEvent(event, Hint());
      expect(result, isNotNull);
      expect(result!.message?.formatted, contains('[REDACTED]'));
      expect(result.message?.formatted, isNot(contains('alex@exemplo.com')));
      expect(result.message?.formatted, isNot(contains('123.456.789-00')));
    });

    test('remove request, user e extra (PHI nunca sai do dispositivo)', () {
      final event = SentryEvent(
        message: SentryMessage('ok'),
        request: SentryRequest(),
        user: SentryUser(id: 'user-1', username: 'alex'),
        // ignore: deprecated_member_use
        extra: <String, dynamic>{'diagnosis': 'hipertensão'},
      );
      final result = redactSentryEvent(event, Hint());
      expect(result, isNotNull);
      expect(result!.request, isNull);
      expect(result.user, isNull);
      // ignore: deprecated_member_use
      expect(result.extra, isEmpty);
    });

    test('filtra tags cuja chave sugere dado sensível', () {
      final event = SentryEvent(
        message: SentryMessage('ok'),
        tags: <String, String>{
          'patient_id': '123',
          'build': '3.1.0',
          'email': 'a@b.com',
          'platform': 'web',
        },
      );
      final result = redactSentryEvent(event, Hint());
      expect(result, isNotNull);
      expect(result!.tags, containsPair('build', '3.1.0'));
      expect(result.tags, containsPair('platform', 'web'));
      expect(result.tags, isNot(contains('patient_id')));
      expect(result.tags, isNot(contains('email')));
    });
  });

  group('setupObservability', () {
    test('é no-op quando SENTRY_DSN não está definido (default)', () async {
      // Sem --dart-define=SENTRY_DSN=..., String.fromEnvironment é vazia e
      // setupObservability retorna imediatamente sem chamar SentryFlutter.init.
      await setupObservability();
      // Sem exceção = contrato respeitado.
    });
  });
}
