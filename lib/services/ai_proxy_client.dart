import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Camada de transporte para o proxy de IA (Cloudflare Worker) usado pelo
/// app irmão React "Remédio na Hora". A chave NVIDIA permanece como secret
/// do Worker; o app chama `/v1/chat/completions` sem credencial nenhuma.
///
/// Proteções replicadas do cliente do PWA:
/// - catálogo `/v1/models` com cache de 5 minutos, para não insistir em
///   modelos que a chave não possui;
/// - no máximo três modelos por operação (resposta rápida mesmo quando um
///   endpoint está lento);
/// - fallback de modelo apenas em falhas que melhoram trocando (403/404/410/
///   429 do upstream/5xx/rede) — limite do proxy e corpo grande não trocam;
/// - `stream: false` sempre (o proxy bloqueia streaming).
///
/// No Flutter web o navegador define o cabeçalho Origin sozinho — a origem
/// publicada do app precisa estar cadastrada em ALLOWED_ORIGINS do Worker.
/// Em plataformas nativas não há navegador: enviamos manualmente a mesma
/// origem autorizada do PWA para passar pela verificação de CORS do proxy.
class AiProxyClient {
  AiProxyClient({
    http.Client? client,
    String? proxyUrl,
    bool? isWebOverride,
  })  : _client = client ?? http.Client(),
        _isWeb = isWebOverride ?? kIsWeb;

  final http.Client _client;
  final bool _isWeb;

  /// Endereço público do Worker (igual ao DEFAULT_PROXY_URL do PWA).
  static const String defaultProxyUrl =
      'https://remedios-ai-proxy.alexsantossp71.workers.dev';

  /// Origem autorizada usada nas chamadas nativas (mesma do PWA React).
  static const String nativeOrigin =
      'https://alexsantossp71-lgtm.github.io';

  static const String defaultTextModel = 'z-ai/glm-5.3-flash';
  static const String defaultVisionModel = 'meta/llama-3.2-90b-vision-instruct';

  /// Lista curada de modelos NVIDIA com endpoint gratuito, na ordem de
  /// preferência para tarefas de texto (igual ao cliente do PWA).
  static const List<String> textFallbacks = [
    'z-ai/glm-5.3-flash',
    'stepfun-ai/step-5-preview',
    'meta/muse-glimmer-30b',
    'nvidia/nemotron-3.5-super-vl-120b-a12b',
    'nvidia/nemotron-3.5-lightning-30b-a3b',
  ];

  static const List<String> visionFallbacks = [
    'meta/llama-3.2-90b-vision-instruct',
    'meta/muse-glimmer-30b',
    'stepfun-ai/step-5-preview',
    'z-ai/glm-5.3-flash',
    'nvidia/nemotron-3.5-super-vl-120b-a12b',
  ];

  static const Duration defaultRequestTimeout = Duration(seconds: 12);
  static const Duration catalogTimeout = Duration(seconds: 8);
  static const Duration catalogTtl = Duration(minutes: 5);

  /// Erro com mensagem já amigável para exibir direto na interface.
  ///
  /// [status] é o HTTP quando o erro veio de uma resposta (null em falha de
  /// rede) — a mesma semântica do `AiError` do PWA.
  AiException exception(String message, {int? status}) =>
      AiException(message, status: status);

  String get proxyUrl => defaultProxyUrl;

  /// Cache do catálogo de modelos, por instância (uma instância por uso
  /// de recurso no app — o TTL de 5 min mantém o custo baixo).
  Set<String>? _catalogIds;
  DateTime? _catalogExpiresAt;

  Map<String, String> _headers() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (!_isWeb) headers['Origin'] = nativeOrigin;
    return headers;
  }

  /// Mensagens no formato OpenAI; [content] pode ser String ou lista de
  /// partes `{'type': 'text'|'image_url', ...}` (igual ao PWA).
  Future<String> chatCompletion({
    required List<Map<String, dynamic>> messages,
    String? model,
    bool hasImages = false,
    int maxTokens = 1024,
    double temperature = 0.2,
    Duration requestTimeout = defaultRequestTimeout,
    int maxModels = 3,
  }) async {
    final preferred = <String>[
      if (model != null && model.trim().isNotEmpty) model.trim(),
      ...(hasImages ? visionFallbacks : textFallbacks),
    ];
    // Sem duplicatas preservando a ordem (Set(...) do PWA).
    final ordered = preferred.toSet().toList();

    final catalog = await _loadCatalogIds();
    final candidates = (catalog == null)
        ? ordered
        : ordered.where((candidate) => catalog.contains(candidate)).toList();
    final modelsToTry = (candidates.isNotEmpty ? candidates : ordered)
        .take(maxModels)
        .toList();

    Object? lastError;
    for (final candidate in modelsToTry) {
      try {
        return await _attempt(
          candidateModel: candidate,
          messages: messages,
          maxTokens: maxTokens,
          temperature: temperature,
          requestTimeout: requestTimeout,
        );
      } on AiException catch (error) {
        lastError = error;
        final status = error.status;
        final detail = error.message.toLowerCase();
        final proxyRateLimited = status == 429 &&
            (detail.contains('limite de uso do proxy') ||
                detail.contains('limite de solicitações atingido'));
        // Falhas de autenticação, corpo grande e limite local do proxy não
        // melhoram trocando de modelo — espelho exato do canFallback do PWA.
        final canFallback = !proxyRateLimited &&
            (status == null ||
                status == 403 ||
                status == 404 ||
                status == 410 ||
                status == 429 ||
                status >= 500);
        if (!canFallback) rethrow;
      } catch (error) {
        lastError = error;
      }
    }
    if (lastError is AiException) throw lastError;
    throw AiException(
      'Não foi possível conectar ao serviço de IA. Verifique a conexão e '
      'tente novamente.',
    );
  }

  Future<String> _attempt({
    required String candidateModel,
    required List<Map<String, dynamic>> messages,
    required int maxTokens,
    required double temperature,
    required Duration requestTimeout,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$defaultProxyUrl/chat/completions'),
            headers: _headers(),
            body: jsonEncode(<String, dynamic>{
              'model': candidateModel,
              'messages': messages,
              'temperature': temperature,
              'max_tokens': maxTokens,
              'stream': false,
            }),
          )
          .timeout(requestTimeout);

      if (response.statusCode != 200) {
        throw AiException(
          describeHttpError(response.statusCode, response.body),
          status: response.statusCode,
        );
      }

      // Navega até choices[0].message.content antes de normalizar —
      // provedores devolvem texto como string ou lista de partes.
      final decoded = jsonDecode(response.body);
      Object? content;
      if (decoded is Map<String, dynamic>) {
        final choices = decoded['choices'];
        if (choices is List && choices.isNotEmpty) {
          final first = choices.first;
          if (first is Map<String, dynamic>) {
            final message = first['message'];
            if (message is Map<String, dynamic>) {
              content = message['content'];
            }
          }
        }
      }

      final text = extractChatContent(content);
      if (text.trim().isEmpty) {
        throw AiException(
          'O modelo respondeu sem conteúdo válido. Tente novamente.',
        );
      }
      return text;
    } on TimeoutException {
      throw AiException(
        'O modelo $candidateModel demorou mais de '
        '${requestTimeout.inSeconds} segundos. Tentando outra opção.',
      );
    } on AiException {
      rethrow;
    } on FormatException {
      throw AiException(
        'O modelo respondeu sem conteúdo válido. Tente novamente.',
      );
    } catch (_) {
      throw AiException(
        'Não foi possível conectar ao serviço de IA. Verifique a conexão e '
        'tente novamente.',
      );
    }
  }

  /// Catálogo de modelos anunciados para a chave do proxy; null quando a
  /// consulta falha (o fallback estático continua disponível).
  Future<Set<String>?> _loadCatalogIds() async {
    final now = DateTime.now();
    final expiresAt = _catalogExpiresAt;
    if (_catalogIds != null &&
        expiresAt != null &&
        expiresAt.isAfter(now)) {
      return _catalogIds;
    }
    try {
      final response = await _client
          .get(
            Uri.parse('$defaultProxyUrl/models'),
            headers: _headers(),
          )
          .timeout(catalogTimeout);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      final data = decoded['data'];
      if (data is! List) return null;
      final ids = data
          .whereType<Map<String, dynamic>>()
          .map((item) => item['id'])
          .whereType<String>()
          .where((id) => id.trim().isNotEmpty)
          .toSet();
      if (ids.isEmpty) return null;
      _catalogIds = ids;
      _catalogExpiresAt = now.add(catalogTtl);
      return ids;
    } catch (_) {
      return null;
    }
  }

  /// Mensagem PT-BR por status — mesma tabela do `describeHttpError` do PWA.
  static String describeHttpError(int status, String body) {
    final detail = readServiceError(body);
    if (status == 401) {
      return detail.isEmpty
          ? 'A autenticação do serviço de IA foi recusada. Verifique a chave '
              'NVIDIA cadastrada no Worker.'
          : detail;
    }
    if (status == 403) {
      return detail.isEmpty
          ? 'O serviço recusou a solicitação. Verifique se o modelo está '
              'autorizado para a conta NVIDIA e na lista permitida do Worker.'
          : detail;
    }
    if (status == 404) {
      return detail.isEmpty
          ? 'O modelo ou endereço solicitado não foi encontrado. Verifique a '
              'configuração do serviço de IA.'
          : detail;
    }
    if (status == 413) {
      return detail.isEmpty
          ? 'A foto ou o texto é muito grande. Escolha uma imagem menor ou '
              'reduza o texto.'
          : detail;
    }
    if (status == 429) {
      return detail.isEmpty
          ? 'O limite de solicitações foi atingido. Aguarde alguns instantes '
              'e tente novamente.'
          : detail;
    }
    if (status >= 500) {
      return detail.isEmpty
          ? 'O serviço de IA está temporariamente indisponível. Tente '
              'novamente mais tarde.'
          : detail;
    }
    return detail.isEmpty
        ? 'A solicitação ao serviço de IA falhou (HTTP $status). Tente '
            'novamente.'
        : detail;
  }

  /// Extrai `error.message` do corpo JSON do proxy (formato OpenAI) ou do
  /// upstream repassado; string vazia quando não há detalhe legível.
  static String readServiceError(String body) {
    if (body.trim().isEmpty) return '';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic>) {
          final message = error['message'];
          if (message is String) return message.trim();
        }
        if (error is String) return error.trim();
        final message = decoded['message'];
        if (message is String) return message.trim();
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  /// Normaliza `message.content` no formato OpenAI: provedores devolvem
  /// texto como string ou como lista de partes text/image; partes sem
  /// texto são ignoradas (mesma regra do `extractChatContent` do PWA).
  static String extractChatContent(Object? value) {
    if (value is String) return value;
    if (value is! List) return '';
    final buffer = StringBuffer();
    for (final part in value) {
      if (part is String) {
        buffer.write(part);
      } else if (part is Map<String, dynamic> && part['text'] is String) {
        buffer.write(part['text'] as String);
      }
    }
    return buffer.toString();
  }
}

/// Exceção amigável do transporte de IA (espelho do `AiError` do PWA).
class AiException implements Exception {
  AiException(this.message, {this.status});

  /// Mensagem pronta para exibir ao usuário.
  final String message;

  /// Status HTTP quando o erro veio de uma resposta; null em falha de rede.
  final int? status;

  @override
  String toString() => message;
}

