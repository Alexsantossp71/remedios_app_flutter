import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:remedios_app_flutter/services/crm_lookup_service.dart';

const _activeJson = {
  'crm': 33333,
  'nome': 'SANDRA LINA DOS REIS ALPENDRE',
  'situacao': 'A',
  'tipoInscricao': 'PRINCIPAL',
  'especialidades': [
    {
      'descricao': 'ENDOCRINOLOGIA E METABOLOGIA',
      'item': 3,
      'grupo': 4,
      'numeroRequerimento': 11026,
      'areaAtuacao': [],
    },
  ],
  'mensagemStatus': null,
  'escolaNome': 'UNIVERSIDADE DE SAO PAULO',
  'nomeLimpo': 'SANDRA LINA DOS REIS ALPENDRE',
};

const _inactiveJson = {
  'crm': 12345,
  'nome': 'FULANO DE TAL',
  'situacao': 'I',
  'especialidades': [],
  'mensagemStatus': 'INATIVO DESDE 20/12/2005',
  'escolaNome': null,
};

http.Client _jsonClient(Object body, {int status = 200}) {
  return MockClient(
    (_) async => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    ),
  );
}

void main() {
  group('CrmLookupService — SP', () {
    test('success maps fields and title-cases name keeping particles lowercase',
        () async {
      final service = CrmLookupService(
        client: _jsonClient(_activeJson),
        isWebOverride: false,
      );

      final result = await service.lookup('33333', 'SP');

      expect(result.kind, CrmLookupKind.success);
      expect(result.name, 'Sandra Lina dos Reis Alpendre');
      expect(result.specialty, 'ENDOCRINOLOGIA E METABOLOGIA');
      expect(result.statusText, 'Ativo');
      expect(result.school, 'UNIVERSIDADE DE SAO PAULO');
    });

    test('inactive CRM reports Inativo with mensagemStatus', () async {
      final service = CrmLookupService(
        client: _jsonClient(_inactiveJson),
        isWebOverride: false,
      );

      final result = await service.lookup('12345', 'SP');

      expect(result.kind, CrmLookupKind.success);
      expect(result.statusText, 'Inativo: INATIVO DESDE 20/12/2005');
      expect(result.specialty, '');
    });

    test('404 returns notFound', () async {
      final service = CrmLookupService(
        client: _jsonClient({'error': 'Not Found'}, status: 404),
        isWebOverride: false,
      );

      final result = await service.lookup('9999999', 'SP');

      expect(result.kind, CrmLookupKind.notFound);
    });

    test('network error returns error result', () async {
      final service = CrmLookupService(
        client: MockClient((_) => throw http.ClientException('offline')),
        isWebOverride: false,
      );

      final result = await service.lookup('33333', 'SP');

      expect(result.kind, CrmLookupKind.error);
      expect(result.message, isNotEmpty);
    });

    test('normalizes CRM to digits only before calling the API', () async {
      Uri? hit;
      final service = CrmLookupService(
        client: MockClient((request) async {
          hit = request.url;
          return http.Response(jsonEncode(_activeJson), 200);
        }),
        isWebOverride: false,
      );

      await service.lookup('33.333', 'sp');

      expect(resultIsSuccess(hit), isTrue);
    });

    test('desktop URL calls CREMESP directly', () async {
      Uri? hit;
      final service = CrmLookupService(
        client: MockClient((request) async {
          hit = request.url;
          return http.Response(jsonEncode(_activeJson), 200);
        }),
        isWebOverride: false,
      );

      await service.lookup('33333', 'SP');

      expect(hit.toString(), 'https://api.cremesp.org.br/guia-medico/medico-info/33333');
    });

    test('web routes through AllOrigins proxy with encoded URL', () async {
      Uri? hit;
      final service = CrmLookupService(
        client: MockClient((request) async {
          hit = request.url;
          return http.Response(jsonEncode(_activeJson), 200);
        }),
        isWebOverride: true,
      );

      await service.lookup('33333', 'SP');

      expect(hit!.host, 'api.allorigins.win');
      expect(
        hit.toString(),
        contains(
          Uri.encodeComponent(
            'https://api.cremesp.org.br/guia-medico/medico-info/33333',
          ),
        ),
      );
    });
  });

  group('CrmLookupService — non-SP', () {
    test('MG returns unsupported without calling the network', () async {
      var called = false;
      final service = CrmLookupService(
        client: MockClient((_) async {
          called = true;
          return http.Response('{}', 200);
        }),
        isWebOverride: false,
      );

      final result = await service.lookup('12345', 'MG');

      expect(result.kind, CrmLookupKind.unsupported);
      expect(result.uf, 'MG');
      expect(called, isFalse);
    });
  });
}

bool resultIsSuccess(Uri? hit) =>
    hit.toString().endsWith('/medico-info/33333');
