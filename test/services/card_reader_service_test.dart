import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:remedios_app_flutter/services/card_reader_service.dart';

void main() {
  group('CardReaderService.parseContent', () {
    test('extrai todos os campos de um JSON válido', () {
      const content = '''
{
  "name": "Nacional Flex",
  "provider": "Unimed",
  "cardNumber": "1234567890123456",
  "groupNumber": "8871",
  "beneficiaryCode": "0900000000000000",
  "validity": "03/2028",
  "coverageType": "Ambulatorial + Hospitalar",
  "notes": "Plano empresarial.",
  "rawText": "UNIMED NACIONAL FLEX"
}
''';

      final result = CardReaderService.parseContent(content);

      expect(result.name, 'Nacional Flex');
      expect(result.provider, 'Unimed');
      expect(result.cardNumber, '1234567890123456');
      expect(result.groupNumber, '8871');
      expect(result.beneficiaryCode, '0900000000000000');
      expect(result.validity, '03/2028');
      expect(result.coverageType, 'Ambulatorial + Hospitalar');
      expect(result.notes, 'Plano empresarial.');
      expect(result.filledFields, 7);
    });

    test('tolera cercas de código e texto antes/depois do JSON', () {
      const content = '''
Aqui está o que encontrei:
```json
{"name": "Blue", "provider": "Bradesco Saúde"}
```
Espero ter ajudado.
''';

      final result = CardReaderService.parseContent(content);

      expect(result.name, 'Blue');
      expect(result.provider, 'Bradesco Saúde');
      expect(result.cardNumber, isNull);
      expect(result.validity, isNull);
    });

    test('remove caracteres não numéricos de números do cartão', () {
      const content =
          '{"name": "Amil", "provider": "Amil", "cardNumber": "0123 456-78", '
          '"groupNumber": "n/d", "beneficiaryCode": "9.0"}';

      final result = CardReaderService.parseContent(content);

      expect(result.cardNumber, '012345678');
      expect(result.groupNumber, isNull);
      expect(result.beneficiaryCode, '90');
    });

    test('lança quando a resposta não contém JSON', () {
      expect(
        () => CardReaderService.parseContent('não consegui ler a imagem'),
        throwsA(isA<CardReaderException>()),
      );
    });

    test('lança quando nenhum dado identificável é retornado', () {
      expect(
        () => CardReaderService.parseContent('{"cardNumber": "123"}'),
        throwsA(isA<CardReaderException>()),
      );
    });
  });

  group('CardReaderService.readCard (proxy)', () {
    const proxyUrl = 'https://proxy.test/api/read-card';

    test('envia base64 e mimeType ao proxy e extrai o resultado', () async {
      final client = _FakeClient(
        statusCode: 200,
        body: '{"content":"{\\"name\\":\\"Golden\\",'
            '\\"provider\\":\\"Porto Seguro\\"}",'
            '"model":"nvidia/llama-3.2-vision"}',
      );
      final service = CardReaderService(client: client, proxyUrl: proxyUrl);
      expect(service.proxyUrl, proxyUrl);

      final result = await service.readCard(
        imageBytes: Uint8List.fromList([137, 80, 78, 71]),
        mimeType: 'image/png',
      );

      expect(result.name, 'Golden');
      expect(result.provider, 'Porto Seguro');

      expect(client.lastUri.toString(), proxyUrl);
      final body = client.lastBody!;
      expect(body, contains('"mimeType":"image/png"'));
      expect(body, contains('"image":"'));
      // Nenhuma chave de API sai do cliente.
      expect(body, isNot(contains('Bearer')));
      expect(client.lastHeaders!.containsKey('Authorization'), isFalse);
    });

    test('usa a URL padrão do proxy de produção', () {
      final service = CardReaderService(client: _FakeClient(statusCode: 200, body: '{}'));
      expect(
        service.proxyUrl,
        'https://remedios-app-flutter.vercel.app/api/read-card',
      );
    });

    test('converte 400 em mensagem de imagem não aceita', () async {
      final service = CardReaderService(
        client: _FakeClient(statusCode: 400, body: '{"error":"invalid_request"}'),
        proxyUrl: proxyUrl,
      );

      await expectLater(
        service.readCard(imageBytes: Uint8List.fromList([1])),
        throwsA(
          isA<CardReaderException>()
              .having((e) => e.message, 'message', contains('não foi aceita')),
        ),
      );
    });

    test('converte 413 em mensagem de imagem grande', () async {
      final service = CardReaderService(
        client: _FakeClient(statusCode: 413, body: '{"error":"image_too_large"}'),
        proxyUrl: proxyUrl,
      );

      await expectLater(
        service.readCard(imageBytes: Uint8List.fromList([1])),
        throwsA(
          isA<CardReaderException>()
              .having((e) => e.message, 'message', contains('muito grande')),
        ),
      );
    });

    test('converte 429 em mensagem de limite diário', () async {
      final service = CardReaderService(
        client: _FakeClient(statusCode: 429, body: '{"error":"rate_limited"}'),
        proxyUrl: proxyUrl,
      );

      await expectLater(
        service.readCard(imageBytes: Uint8List.fromList([1])),
        throwsA(
          isA<CardReaderException>()
              .having((e) => e.message, 'message', contains('Limite diário')),
        ),
      );
    });

    test('converte 502 em mensagem de leitura indisponível', () async {
      final service = CardReaderService(
        client: _FakeClient(statusCode: 502, body: '{"error":"unreadable"}'),
        proxyUrl: proxyUrl,
      );

      await expectLater(
        service.readCard(imageBytes: Uint8List.fromList([1])),
        throwsA(
          isA<CardReaderException>()
              .having((e) => e.message, 'message', contains('indisponível')),
        ),
      );
    });

    test('converte falha de rede em mensagem de conexão', () async {
      final service = CardReaderService(
        client: _ThrowingClient(),
        proxyUrl: proxyUrl,
      );

      await expectLater(
        service.readCard(imageBytes: Uint8List.fromList([1])),
        throwsA(
          isA<CardReaderException>()
              .having((e) => e.message, 'message', contains('conexão')),
        ),
      );
    });
  });
}

class _FakeClient extends http.BaseClient {
  _FakeClient({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
  String? lastBody;
  Uri? lastUri;
  Map<String, String>? lastHeaders;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastBody = await (request as http.Request).finalize().bytesToString();
    lastUri = request.url;
    lastHeaders = request.headers;
    return http.StreamedResponse(
      Stream<List<int>>.value(body.codeUnits),
      statusCode,
    );
  }
}

class _ThrowingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw http.ClientException('no route to host');
  }
}