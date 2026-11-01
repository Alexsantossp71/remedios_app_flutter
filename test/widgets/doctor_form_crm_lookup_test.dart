import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:remedios_app_flutter/services/crm_lookup_service.dart';
import 'package:remedios_app_flutter/widgets/doctor_form_dialog.dart';

const _spJson = {
  'crm': 33333,
  'nome': 'SANDRA LINA DOS REIS ALPENDRE',
  'situacao': 'A',
  'especialidades': [
    {'descricao': 'ENDOCRINOLOGIA E METABOLOGIA'},
  ],
  'mensagemStatus': null,
  'escolaNome': 'USP',
};

http.Client _spClient() => MockClient(
      (_) async => http.Response(jsonEncode(_spJson), 200),
    );

Widget buildSubject({CrmLookupService? crmLookup}) {
  return MaterialApp(
    home: Scaffold(body: DoctorFormDialog(crmLookup: crmLookup)),
  );
}

/// V4 em passos: CRM/UF ficam no passo 2 — preenche o nome e avança.
Future<void> goToStep2(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Nome do médico'),
    'Dra. Teste',
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Continuar'));
  await tester.pumpAndSettle();
}

Future<void> selectCrmUf(WidgetTester tester, String uf) async {
  await tester.tap(find.byKey(const ValueKey('crmStateUf')));
  await tester.pumpAndSettle();
  // No shell em passos há vários Scrollables (PageView, passos); o menu do
  // dropdown é um ListView na overlay — o último da árvore.
  await tester.dragUntilVisible(
    find.text(uf),
    find.byType(ListView).last,
    const Offset(0, -200),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(uf).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lookup button prefills name and specialty from CREMESP',
      (tester) async {
    await tester.pumpWidget(
      buildSubject(crmLookup: CrmLookupService(client: _spClient())),
    );
    await tester.pumpAndSettle();
    await goToStep2(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'CRM'),
      '33333',
    );
    await selectCrmUf(tester, 'SP');

    await tester.tap(find.byTooltip('Buscar dados pelo CRM no conselho'));
    await tester.pumpAndSettle();

    // Como o nome já está preenchido (necessário para avançar o passo 1),
    // o lookup pergunta antes de substituir.
    if (find.text('Substituir').evaluate().isNotEmpty) {
      await tester.tap(find.text('Substituir'));
      await tester.pumpAndSettle();
    }

    expect(find.textContaining('CRM ativo:'), findsOneWidget);

    // Nome e especialidade moram no passo 1: volta para conferir o
    // preenchimento vindo do conselho.
    await tester.tap(find.text('Voltar'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(TextFormField, 'Sandra Lina dos Reis Alpendre'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(TextFormField, 'ENDOCRINOLOGIA E METABOLOGIA'),
      findsOneWidget,
    );
  });

  testWidgets('lookup without UF shows a warning and does not call the API',
      (tester) async {
    var called = false;
    final service = CrmLookupService(
      client: MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );
    await tester.pumpWidget(buildSubject(crmLookup: service));
    await tester.pumpAndSettle();
    await goToStep2(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'CRM'),
      '33333',
    );
    await tester.tap(find.byTooltip('Buscar dados pelo CRM no conselho'));
    await tester.pumpAndSettle();

    expect(called, isFalse);
    expect(find.textContaining('Selecione a UF do CRM'), findsOneWidget);
  });

  testWidgets('MG shows unsupported message and keeps fields manual',
      (tester) async {
    await tester.pumpWidget(
      buildSubject(crmLookup: CrmLookupService(client: _spClient())),
    );
    await tester.pumpAndSettle();
    await goToStep2(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'CRM'),
      '33333',
    );
    await selectCrmUf(tester, 'MG');

    await tester.tap(find.byTooltip('Buscar dados pelo CRM no conselho'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Estado ainda não coberto'), findsOneWidget);
    expect(
      find.widgetWithText(TextFormField, 'Sandra Lina dos Reis Alpendre'),
      findsNothing,
    );
  });
}
