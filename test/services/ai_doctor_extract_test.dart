import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:remedios_app_flutter/services/ai_proxy_client.dart';
import 'package:remedios_app_flutter/services/ai_service.dart';

/// Regressões da extração de médico por texto: a IA só transcreve o que o
/// usuário colou — especialidade entra APENAS pela lista fixa do cadastro,
/// UF tem que ser válida no Brasil e nada é inventado.

http.Response chat(String content) => http.Response(
      jsonEncode({
        'choices': [
          {
            'message': {'content': content},
            'finish_reason': 'stop',
          },
        ],
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

AiService serviceWith(
  http.Client client,
  List<http.Request> requests,
) => AiService(
      proxyClient: AiProxyClient(client: RecordingClient(client, requests)),
    );

/// Grava os requests para os testes afirmarem o que foi enviado.
class RecordingClient extends http.BaseClient {
  RecordingClient(this.inner, this.requests);

  final http.Client inner;
  final List<http.Request> requests;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest baseRequest) async {
    final request = baseRequest as http.Request;
    requests.add(request);
    final response = await inner.send(request);
    return http.StreamedResponse(
      response.stream,
      response.statusCode,
      headers: response.headers,
    );
  }
}

void main() {
  final requests = <http.Request>[];
  late AiService service;

  setUp(() {
    requests.clear();
  });

  AiService withPayload(String content) {
    service = serviceWith(
      MockClient((_) async => chat(content)),
      requests,
    );
    return service;
  }

  group('extractDoctorData', () {
    test('extrai nome, especialidade, CRM, UF e telefone do texto', () async {
      service = withPayload(
        jsonEncode({
          'nome': 'Dra. Ana Silva',
          'especialidade': 'Cardiologia',
          'crm': '123456',
          'uf': 'SP',
          'telefone': '(11) 98888-7777',
        }),
      );

      final data = await service.extractDoctorData(
        'Minha médica: Dra. Ana Silva, CRM 123456-SP, cardiologista, '
        'fone (11) 98888-7777',
      );

      expect(data.name, 'Ana Silva');
      expect(data.specialty, 'Cardiologia');
      expect(data.crm, '123456');
      expect(data.crmState, 'SP');
      expect(data.phone, '(11) 98888-7777');
      expect(data.isEmpty, isFalse);

      // O prompt envia a lista fixa: a especialidade tem que ser escolhida
      // dentro dela, não inventada. O proxy também faz um GET /v1/models
      // de catálogo antes — filtra só o chat.
      final chatRequests =
          requests
              .where((request) => request.url.path.contains('chat/completions'))
              .toList();
      expect(chatRequests, hasLength(1));
      expect(chatRequests.single.body, contains('Cardiologia'));
      expect(chatRequests.single.body, contains('Minha médica'));
    });

    test('tira o prefixo Dr./Dra. e corrige espaços', () async {
      service = withPayload(
        jsonEncode({
          'nome': 'Dr.  João   da Silva',
          'especialidade': '',
          'crm': '',
          'uf': '',
          'telefone': '',
        }),
      );

      final data = await service.extractDoctorData('Dr. João da Silva');
      expect(data.name, 'João da Silva');
    });

    test('especialidade fora da lista fixa volta vazia', () async {
      service = withPayload(
        jsonEncode({
          'nome': 'Bruna Costa',
          'especialidade': 'Nutrição Esportiva',
          'crm': '',
          'uf': '',
          'telefone': '',
        }),
      );

      final data = await service.extractDoctorData(
        'Bruna Costa, nutricionista esportiva',
      );
      expect(data.name, 'Bruna Costa');
      expect(data.specialty, isEmpty);
    });

    test('escrita diferente da lista casa sem quebrar o cadastro', () async {
      service = withPayload(
        jsonEncode({
          'nome': 'Marcos Lima',
          'especialidade': 'cardiologia',
          'crm': '',
          'uf': '',
          'telefone': '',
        }),
      );

      final data = await service.extractDoctorData('Marcos Lima cardiologista');
      expect(data.specialty, 'Cardiologia');
    });

    test('CRM com pontuação vira só dígitos', () async {
      service = withPayload(
        jsonEncode({
          'nome': '',
          'especialidade': '',
          'crm': '123.456-7',
          'uf': '',
          'telefone': '',
        }),
      );

      final data = await service.extractDoctorData('CRM 123.456-7');
      expect(data.crm, '1234567');
    });

    test('UF inválida (ou estrangeira) é descartada', () async {
      service = withPayload(
        jsonEncode({
          'nome': '',
          'especialidade': '',
          'crm': '123456',
          'uf': 'ZZ',
          'telefone': '',
        }),
      );

      final data = await service.extractDoctorData('CRM 123456');
      expect(data.crm, '123456');
      expect(data.crmState, isEmpty);
    });

    test('lê JSON cercado de texto e blocos de código', () async {
      service = withPayload(
        'Claro!\n```json\n'
        '{"nome":"Ana","especialidade":"Clínica Médica","crm":"","uf":"",'
        '"telefone":""}\n'
        '```',
      );

      final data = await service.extractDoctorData('Dra. Ana');
      expect(data.name, 'Ana');
      expect(data.specialty, 'Clínica Médica');
    });

    test('texto que não descreve médico lança mensagem amigável', () async {
      service = withPayload(jsonEncode({'error': 'not_a_doctor'}));

      await expectLater(
        service.extractDoctorData('compre leite e pão'),
        throwsA(
          isA<AiException>().having(
            (e) => e.message,
            'message',
            contains('não parece conter dados de um médico'),
          ),
        ),
      );
    });

    test('resposta sem nenhum dado aproveitável lança', () async {
      service = withPayload(
        jsonEncode({
          'nome': '',
          'especialidade': '',
          'crm': '',
          'uf': '',
          'telefone': '',
        }),
      );

      await expectLater(
        service.extractDoctorData('qualquer coisa'),
        throwsA(
          isA<AiException>().having(
            (e) => e.message,
            'message',
            contains('não encontrou dados do médico'),
          ),
        ),
      );
    });

    test('texto vazio lança antes de chamar a rede', () async {
      service = withPayload(jsonEncode({}));

      await expectLater(
        service.extractDoctorData('   '),
        throwsA(
          isA<AiException>().having(
            (e) => e.message,
            'message',
            contains('Cole ou digite os dados'),
          ),
        ),
      );
      expect(requests, isEmpty);
    });
  });

  group('sanitizeDoctorData', () {
    test('entrada estranha nunca lança — vira campos vazios', () {
      final data = sanitizeDoctorData('não sou um mapa');
      expect(data.isEmpty, isTrue);
    });

    test('campos ausentes no mapa viram string vazia', () {
      final data = sanitizeDoctorData({'nome': 'Ana'});
      expect(data.name, 'Ana');
      expect(data.crm, isEmpty);
      expect(data.crmState, isEmpty);
      expect(data.specialty, isEmpty);
      expect(data.phone, isEmpty);
    });
  });
}
