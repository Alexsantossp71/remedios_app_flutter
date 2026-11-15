import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:remedios_app_flutter/services/ai_proxy_client.dart';
import 'package:remedios_app_flutter/services/ai_service.dart';

/// Cliente falso que registra pedidos e responde conforme o cenário.
class FakeClient extends http.BaseClient {
  FakeClient(this.handler);

  final Future<http.Response> Function(http.Request request) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest baseRequest) async {
    final request = baseRequest as http.Request;
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

Future<http.Response> Function(http.Request) _catalogAndChat(String content) {
  return (request) async {
    if (request.method == 'GET' && request.url.path.endsWith('/models')) {
      return _json({
        'data': [
          {'id': AiProxyClient.defaultVisionModel},
        ],
      });
    }
    return _json({
      'choices': [
        {
          'message': {'content': content},
        },
      ],
    });
  };
}

void main() {
  group('AiService.extractLabValues', () {
    test('envia a foto ao modelo de visão e devolve valores sanitizados',
        () async {
      final requests = <http.Request>[];
      final client = FakeClient((request) async {
        requests.add(request);
        return _catalogAndChat(
          '{"labName":"Lab Central","examDate":"2026-11-12","resultados":['
          '{"examName":"Glicemia","value":"115","unit":"mg/dL",'
          '"reference":"70 - 99"},'
          '{"examName":"Hemoglobina","value":"14,5","unit":"g/dL",'
          '"reference":"12 a 16"}]}',
        )(request);
      });

      final service = AiService(
        proxyClient: AiProxyClient(client: client, isWebOverride: false),
      );
      final result = await service.extractLabValues(
        imageBytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/jpeg',
      );

      expect(result.labName, 'Lab Central');
      expect(result.examDate, '2026-11-12');
      expect(result.values.length, 2);
      // Flags calculadas no app, não pela IA:
      expect(result.values[0].flag, 'high');
      expect(result.values[1].flag, 'normal');

      final chat = requests.firstWhere(
        (r) => r.method == 'POST' && r.url.path.endsWith('/chat/completions'),
      );
      final body = jsonDecode(chat.body) as Map<String, dynamic>;
      expect(body['model'], AiProxyClient.defaultVisionModel);
      expect(body['max_tokens'], 5000,
          reason: 'laudo real de 8 itens queimou 2.624 tokens de raciocínio '
              '(E2E): o orçamento de 2.000 truncava o JSON no meio e a '
              'leitura falhava sempre');
    });

    test('conteúdo com partes text/image é normalizado', () async {
      final client = FakeClient(
        (request) async {
          if (request.method == 'GET' &&
              request.url.path.endsWith('/models')) {
            return _json({
              'data': [
                {'id': AiProxyClient.defaultVisionModel},
              ],
            });
          }
          return _json({
            'choices': [
              {
                'message': {
                  'content': [
                    {'type': 'text', 'text': '{"labName":"","examDate":"",'},
                    {'type': 'image_url', 'image_url': {'url': 'x'}},
                    {
                      'type': 'text',
                      'text':
                          '"resultados":[{"examName":"TSH","value":"2,1"}]}',
                    },
                  ],
                },
              },
            ],
          });
        },
      );

      final service = AiService(
        proxyClient: AiProxyClient(client: client, isWebOverride: false),
      );
      final result = await service.extractLabValues(
        imageBytes: Uint8List.fromList([1]),
        mimeType: 'image/jpeg',
      );
      expect(result.values.single.examName, 'TSH');
      expect(result.values.single.numericValue, 2.1);
    });

    test('not_a_report devolve mensagem amigável', () async {
      final client = FakeClient(
        (request) async => _catalogAndChat('{"error":"not_a_report"}')(request),
      );
      final service = AiService(
        proxyClient: AiProxyClient(client: client, isWebOverride: false),
      );

      await expectLater(
        service.extractLabValues(
          imageBytes: Uint8List.fromList([1]),
          mimeType: 'image/jpeg',
        ),
        throwsA(isA<AiException>().having(
          (e) => e.message,
          'message',
          contains('não parece ser um laudo'),
        )),
      );
    });

    test('laudo sem valores reconhecidos pede foto melhor', () async {
      final client = FakeClient(
        (request) async => _catalogAndChat(
          '{"labName":"X","examDate":"","resultados":[]}',
        )(request),
      );
      final service = AiService(
        proxyClient: AiProxyClient(client: client, isWebOverride: false),
      );

      await expectLater(
        service.extractLabValues(
          imageBytes: Uint8List.fromList([1]),
          mimeType: 'image/jpeg',
        ),
        throwsA(isA<AiException>().having(
          (e) => e.message,
          'message',
          contains('não reconheceu valores'),
        )),
      );
    });
  });
}
