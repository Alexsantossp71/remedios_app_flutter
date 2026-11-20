import 'package:sentry_flutter/sentry_flutter.dart';

/// Observabilidade de falhas em produção (P3-2 da auditoria arquitetural).
///
/// O Sentry é **dormant por default**: só inicializa quando o DSN é fornecido
/// em tempo de build (`--dart-define=SENTRY_DSN=https://...@sentry.io/ID`).
/// Sem o DSN, [setupObservability] é no-op e nenhum dado sai do dispositivo.
///
/// Minimização de dados (LGPD art. 18 + natureza clínica do app): o
/// [redactSentryEvent] (configurado como `beforeSend`) remove request
/// bodies/headers, dados de usuário (IP/email/nome) e redacta PII/PHI em
/// mensagens antes de qualquer envio. A função é pura e testável sem DSN.

/// Padrões de PII/PHI que nunca devem sair do dispositivo num report de erro.
final List<RegExp> _redactionPatterns = <RegExp>[
  // E-mail.
  RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'),
  // CPF (com ou sem pontuação).
  RegExp(r'\b\d{3}\.?\d{3}\.?\d{3}-?\d{2}\b'),
  // Telefone brasileiro (com DDD, 8 ou 9 dígitos).
  RegExp(r'\(?\d{2}\)?\s?9?\d{4}-?\d{4}'),
  // Cartão de 16 dígitos (com ou sem espaços).
  RegExp(r'\b\d{4}\s?\d{4}\s?\d{4}\s?\d{4}\b'),
];

/// Substitui cada padrão de PII por `[REDACTED]`.
String redactPii(String input) {
  var output = input;
  for (final pattern in _redactionPatterns) {
    output = output.replaceAll(pattern, '[REDACTED]');
  }
  return output;
}

/// `beforeSend` do Sentry: minimiza dados sensíveis antes do envio.
///
/// - Redacta PII (e-mail/CPF/telefone/cartão) na mensagem formatada.
/// - Remove `request` (headers/bodies podem conter dados clínicos).
/// - Remove `user` (IP/email/username nunca são enviados).
/// - Descarta `extra` (pode conter PHI injetado por acidente).
/// - Filtra `tags` cuja chave sugere dado sensível.
SentryEvent? redactSentryEvent(SentryEvent event, Hint hint) {
  final formatted = event.message?.formatted;
  final redacted = formatted != null ? redactPii(formatted) : null;

  final filteredTags = Map<String, String>.fromEntries(
    event.tags.entries.where(
      (entry) => !_looksSensitive(entry.key),
    ),
  );

  return event.copyWith(
    message: redacted != null && redacted != formatted
        ? SentryMessage(redacted)
        : event.message,
    request: null,
    user: null,
    extra: const <String, dynamic>{},
    tags: filteredTags,
  );
}

bool _looksSensitive(String key) {
  final lower = key.toLowerCase();
  return lower.contains('email') ||
      lower.contains('cpf') ||
      lower.contains('phone') ||
      lower.contains('tel') ||
      lower.contains('name') ||
      lower.contains('token') ||
      lower.contains('password') ||
      lower.contains('health') ||
      lower.contains('medical') ||
      lower.contains('patient') ||
      lower.contains('diagnosis');
}

/// Inicializa o Sentry apenas se `SENTRY_DSN` foi definido em tempo de build.
///
/// Chame uma única vez no boot (`main`), antes de `runApp`. Sem o DSN, retorna
/// imediatamente — o app roda sem telemetria e nenhum dado sensível sai.
Future<void> setupObservability() async {
  const dsn = String.fromEnvironment('SENTRY_DSN');
  if (dsn.isEmpty) return;

  await SentryFlutter.init(
    (options) {
      options.dsn = dsn;
      // Nunca anexar PII automática (IP, headers, etc.).
      options.sendDefaultPii = false;
      options.beforeSend = redactSentryEvent;
      // O app lida com dados de saúde: não capturar breadcrumbs de UI que
      // podem conter PHI (toques em campos de formulário, por exemplo).
      options.maxBreadcrumbs = 20;
    },
  );
}
