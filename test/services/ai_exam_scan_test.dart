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

/// Responde ao catálogo com os modelos esperados e ao chat com [content].
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
  group('sanitizeExamScan', () {
    test('normaliza os campos reconhecidos no pedido', () {
      final scan = sanitizeExamScan({
        'name': ' Hemograma completo, Glicemia em jejum ',
        'category': 'Laboratório',
        'doctorName': 'Dra. Ana Lima',
        'place': 'Laboratório Central',
        'date': '2026-11-12',
      });
      expect(scan.name, 'Hemograma completo, Glicemia em jejum');
      expect(scan.category, 'Laboratório');
      expect(scan.doctorName, 'Dra. Ana Lima');
      expect(scan.place, 'Laboratório Central');
      expect(scan.date, '2026-11-12');
    });

    test('categoria fora da lista fixa vira vazio (IA não decide)', () {
      final scan = sanitizeExamScan({
        'name': 'Ultrassom',
        'category': 'Radiologia',
        'date': '2026-11-12',
      });
      expect(scan.category, '');
    });

    test('data fora do formato AAAA-MM-DD vira vazia', () {
      final scan = sanitizeExamScan({
        'name': 'Ultrassom',
        'date': '12/11/2026',
      });
      expect(scan.date, '');
    });

    test('entrada estranha nunca lança — vira campos vazios', () {
      final scan = sanitizeExamScan(null);
      expect(scan.name, '');
      expect(scan.category, '');
      expect(scan.doctorName, '');
      expect(scan.place, '');
      expect(scan.date, '');
    });
  });

  group('AiService.scanExamRequest', () {
    test('envia mensagem de visão e devolve os campos lidos', () async {
      final requests = <http.Request>[];
      final client = FakeClient((request) async {
        requests.add(request);
        return _catalogAndChat(
          '{"name":"Hemograma completo","category":"Laboratório",'
          '"doctorName":"Dr. Bruno","place":"","date":"2026-11-10"}',
        )(request);
      });

      final service = AiService(
        proxyClient: AiProxyClient(client: client, isWebOverride: false),
      );
      final scan = await service.scanExamRequest(
        imageBytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/jpeg',
      );

      expect(scan.name, 'Hemograma completo');
      expect(scan.category, 'Laboratório');
      expect(scan.doctorName, 'Dr. Bruno');

      final chat = requests.firstWhere(
        (r) => r.method == 'POST' && r.url.path.endsWith('/chat/completions'),
      );
      final body = jsonDecode(chat.body) as Map<String, dynamic>;
      expect(
        body['model'],
        AiProxyClient.defaultVisionModel,
        reason: 'leitura de documento usa o modelo de visão',
      );
      final content = (body['messages'][0]['content'] as List).first
          as Map<String, dynamic>;
      expect(content['type'], 'image_url');
      expect(
        (content['image_url'] as Map)['url'],
        startsWith('data:image/jpeg;base64,'),
      );
    });

    test('not_a_request devolve mensagem amigável', () async {
      final client = FakeClient(
        (request) async => _catalogAndChat('{"error":"not_a_request"}')(request),
      );
      final service = AiService(
        proxyClient: AiProxyClient(client: client, isWebOverride: false),
      );

      await expectLater(
        service.scanExamRequest(
          imageBytes: Uint8List.fromList([1]),
          mimeType: 'image/jpeg',
        ),
        throwsA(isA<AiException>().having(
          (e) => e.message,
          'message',
          contains('não parece ser um pedido de exame'),
        )),
      );
    });

    test('resposta sem nome de exame pede foto melhor ou digitação', () async {
      final client = FakeClient(
        (request) async => _catalogAndChat(
          '{"name":"","category":"","doctorName":"","place":"","date":""}',
        )(request),
      );
      final service = AiService(
        proxyClient: AiProxyClient(client: client, isWebOverride: false),
      );

      await expectLater(
        service.scanExamRequest(
          imageBytes: Uint8List.fromList([1]),
          mimeType: 'image/jpeg',
        ),
        throwsA(isA<AiException>().having(
          (e) => e.message,
          'message',
          contains('não reconheceu os dados'),
        )),
      );
    });
  });
}
