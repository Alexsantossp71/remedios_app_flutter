import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:remedios_app_flutter/services/places_search_service.dart';

void main() {
  test('converte o JSON do proxy em sugestões', () async {
    final service = PlacesSearchService(
      client: MockClient((request) async {
        expect(
          request.url.host,
          'remedios-app-flutter.vercel.app',
        );
        expect(request.url.path, '/api/places');
        expect(request.url.queryParameters['q'], 'Rua Ada Pereira');
        return http.Response(
          jsonEncode({
            'results': [
              {
                'label': 'Rua Ada Pereira, 150, Campinas, São Paulo, Brasil',
                'street': 'Rua Ada Pereira',
                'number': '150',
                'neighborhood': 'Cambuí',
                'city': 'Campinas',
                'uf': 'SP',
                'postalCode': '13024-010',
              },
              {'label': ''},
            ],
          }),
          200,
        );
      }),
    );

    final results = await service.search('Rua Ada Pereira');
    expect(results, hasLength(1));
    expect(results.first.street, 'Rua Ada Pereira');
    expect(results.first.number, '150');
    expect(results.first.city, 'Campinas');
    expect(results.first.uf, 'SP');
    expect(results.first.hasAddressData, isTrue);
  });

  test('erro do proxy devolve lista vazia (formulário segue manual)', () async {
    final service = PlacesSearchService(
      client: MockClient((_) async => http.Response('{"error":"x"}', 502)),
    );
    expect(await service.search('Rua Ada Pereira'), isEmpty);
  });

  test('query curta não chega a chamar o proxy', () async {
    var called = false;
    final service = PlacesSearchService(
      client: MockClient((_) async {
        called = true;
        return http.Response(jsonEncode({'results': []}), 200);
      }),
    );
    expect(await service.search('Ru'), isEmpty);
    expect(called, isFalse);
  });
}
