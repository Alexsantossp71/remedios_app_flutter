import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:remedios_app_flutter/services/places_search_service.dart';
import 'package:remedios_app_flutter/widgets/doctor_form_dialog.dart';

http.Client _osmClient() => MockClient(
      (request) async {
        expect(
          request.url.toString(),
          contains('https://remedios-app-flutter.vercel.app/api/places'),
        );
        expect(request.url.queryParameters['q'], 'Rua Ada Pereira Campinas');
        return http.Response(
          jsonEncode({
            'results': [
              {
                'label':
                    'Rua Ada Pereira, 150, Cambuí, Campinas, São Paulo, 13024-010, Brasil',
                'street': 'Rua Ada Pereira',
                'number': '150',
                'neighborhood': 'Cambuí',
                'city': 'Campinas',
                'uf': 'SP',
                'postalCode': '13024-010',
              },
            ],
            'attribution': '© OpenStreetMap contributors',
          }),
          200,
        );
      },
    );

void main() {
  testWidgets(
      'busca de endereço preenche rua, número, bairro, cidade, UF e CEP',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DoctorFormDialog(
            placesSearch: PlacesSearchService(client: _osmClient()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Mostra os campos estruturados antes da escolha (a busca preenche).
    // O diálogo é rolável: garante o botão na tela antes de tocar.
    await tester.ensureVisible(find.text('Preencher endereço sem CEP'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preencher endereço sem CEP'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Buscar endereço'),
      'Rua Ada Pereira Campinas',
    );
    // Debounce de 450ms + ida e volta da rede.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(find.byType(ListTile), findsOneWidget);

    await tester.ensureVisible(find.byType(ListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, 'Rua Ada Pereira'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '150'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Cambuí'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Campinas'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '13024-010'), findsOneWidget);
  });

  testWidgets('falha de rede deixa o autocomplete silencioso e o formulário manual',
      (tester) async {
    final failing = PlacesSearchService(
      client: MockClient((_) async => http.Response('boom', 502)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DoctorFormDialog(placesSearch: failing)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Buscar endereço'),
      'Rua Ada Pereira Campinas',
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('texto curto demais nem chama o serviço', (tester) async {
    var called = false;
    final service = PlacesSearchService(
      client: MockClient((_) async {
        called = true;
        return http.Response(jsonEncode({'results': []}), 200);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DoctorFormDialog(placesSearch: service)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Buscar endereço'),
      'Ru',
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(called, isFalse);
  });
}
