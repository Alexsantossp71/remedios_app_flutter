import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:remedios_app_flutter/services/ai_proxy_client.dart';

/// Registra pedidos e responde conforme o cenário do teste.
class RecordingClient extends http.BaseClient {
  RecordingClient(this.handler);

  final Future<http.Response> Function(http.Request request) handler;

  final List<http.Request> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest baseRequest) async {
    final request = baseRequest as http.Request;
    requests.add(request);
    final response = await handler(request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(response.body)),
      response.statusCode,
      headers: response.headers,
    );
  }
}

http.Response _json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

http.Response _chatContent(String content, {int status = 200}) =>
    _json({
      'choices': [
        {'message': {'content': content}, 'finish_reason': 'stop'},
      ],
    }, status: status);

void main() {
  group('AiProxyClient — cabeçalhos', () {
    test('nativo envia Origin autorizada e Content-Type JSON', () async {
      final client = RecordingClient((request) async => _chatContent('ok'));
      final proxy = AiProxyClient(client: client, isWebOverride: false);
      await proxy.chatCompletion(messages: [
        {'role': 'user', 'content': 'olá'},
      ]);

      expect(client.requests, isNotEmpty);
      final post = client.requests.firstWhere((r) => r.method == 'POST');
      expect(post.headers['Origin'], AiProxyClient.nativeOrigin);
      expect(post.headers['Content-Type'], 'application/json');
    });

    test('web não força Origin (o navegador decide)', () async {
      final client = RecordingClient((request) async => _chatContent('ok'));
      final proxy = AiProxyClient(client: client, isWebOverride: true);
      await proxy.chatCompletion(messages: [
        {'role': 'user', 'content': 'olá'},
      ]);

      final post = client.requests.firstWhere((r) => r.method == 'POST');
      expect(post.headers.containsKey('Origin'), isFalse);
    });

    test('corpo do pedido é o formato OpenAI sem streaming', () async {
      final client = RecordingClient((request) async => _chatContent('ok'));
      final proxy = AiProxyClient(client: client, isWebOverride: false);
      await proxy.chatCompletion(
        messages: [
          {'role': 'user', 'content': 'olá'},
        ],
        maxTokens: 512,
        temperature: 0.3,
      );

      final body = jsonDecode(client.requests.last.body) as Map<String, dynamic>;
      expect(body['stream'], isFalse);
      expect(body['max_tokens'], 512);
      expect(body['temperature'], 0.3);
      expect(body['messages'], isA<List<dynamic>>());
    });
  });

  group('AiProxyClient — fallback de modelos', () {
    test('403 no primeiro modelo tenta o próximo e devolve conteúdo',
        () async {
      final usedModels = <String>[];
      final client = RecordingClient((request) async {
        if (request.url.path.endsWith('/models')) {
          return http.Response('', 404); // sem catálogo: usa lista estática
        }
        usedModels.add(jsonDecode(request.body)['model'] as String);
        if (usedModels.length == 1) {
          return http.Response(
            jsonEncode({'error': {'message': 'Modelo não permitido'}}),
            403,
          );
        }
        return _chatContent('resposta fina');
      });

      final proxy = AiProxyClient(client: client, isWebOverride: false);
      final content = await proxy.chatCompletion(messages: [
        {'role': 'user', 'content': 'olá'},
      ]);

      expect(content, 'resposta fina');
      expect(usedModels.first, AiProxyClient.textFallbacks.first);
      expect(usedModels[1], AiProxyClient.textFallbacks[1]);
    });

    test('catálogo /models filtra candidatos fora da conta', () async {
      final usedModels = <String>[];
      final client = RecordingClient((request) async {
        if (request.url.path.endsWith('/models')) {
          // Só este modelo existe na conta; z-ai/glm-5.3-flash não.
          return _json({'data': [
            {'id': 'stepfun-ai/step-5-preview'},
          ]});
        }
        usedModels.add(jsonDecode(request.body)['model'] as String);
        return _chatContent('feito');
      });

      final proxy = AiProxyClient(client: client, isWebOverride: false);
      final content = await proxy.chatCompletion(messages: [
        {'role': 'user', 'content': 'olá'},
      ]);

      expect(content, 'feito');
      expect(usedModels, ['stepfun-ai/step-5-preview']);
    });

    test('429 do limite do proxy NÃO troca de modelo', () async {
      var chatRequests = 0;
      final client = RecordingClient((request) async {
        if (request.url.path.endsWith('/models')) {
          return http.Response('', 404);
        }
        chatRequests++;
        return http.Response(
          jsonEncode({
            'error': {
              'message': 'Limite de uso do proxy atingido. Tente novamente em ~30s.',
            },
          }),
          429,
        );
      });

      final proxy = AiProxyClient(client: client, isWebOverride: false);

      await expectLater(
        proxy.chatCompletion(messages: [
          {'role': 'user', 'content': 'olá'},
        ]),
        throwsA(isA<AiException>()),
      );
      expect(chatRequests, 1);
    });

    test('resposta vazia lança mensagem amigável', () async {
      final client = RecordingClient(
        (request) async => _chatContent('   '),
      );
      final proxy = AiProxyClient(client: client, isWebOverride: false);

      await expectLater(
        proxy.chatCompletion(messages: [
          {'role': 'user', 'content': 'olá'},
        ]),
        throwsA(
          isA<AiException>().having(
            (e) => e.message,
            'message',
            contains('sem conteúdo válido'),
          ),
        ),
      );
    });
  });

  group('AiProxyClient — extração de conteúdo', () {
    test('extractChatContent aceita string e lista de partes', () {
      expect(AiProxyClient.extractChatContent('texto'), 'texto');
      expect(
        AiProxyClient.extractChatContent([
          {'type': 'text', 'text': 'par'},
          {'type': 'image_url', 'image_url': {'url': 'x'}},
          {'type': 'text', 'text': 'te'},
        ]),
        'parte',
      );
      expect(AiProxyClient.extractChatContent(null), '');
    });

    test('readServiceError lê error.message do proxy e do upstream', () {
      expect(
        AiProxyClient.readServiceError(
          jsonEncode({'error': {'message': 'boom'}}),
        ),
        'boom',
      );
      expect(AiProxyClient.readServiceError('não é json'), '');
    });

    test('describeHttpError traduz os status principais', () {
      expect(AiProxyClient.describeHttpError(401, ''), contains('autenticação'));
      expect(AiProxyClient.describeHttpError(413, ''), contains('grande'));
      expect(AiProxyClient.describeHttpError(500, ''), contains('indisponível'));
      expect(
        AiProxyClient.describeHttpError(418, ''),
        contains('HTTP 418'),
      );
      expect(
        AiProxyClient.describeHttpError(
          429,
          jsonEncode({'error': {'message': 'Detalhe do upstream'}}),
        ),
        'Detalhe do upstream',
      );
      // Corpo não-JSON volta à mensagem padrão (port fiel do React).
      expect(
        AiProxyClient.describeHttpError(429, 'Detalhe do upstream'),
        contains('limite de solicitações'),
      );
    });
  });
}
