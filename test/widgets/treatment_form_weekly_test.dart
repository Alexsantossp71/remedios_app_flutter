import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:remedios_app_flutter/models/treatment.dart';
import 'package:remedios_app_flutter/widgets/treatment_form_dialog.dart';

/// Frequência "Semanal" no formulário: chips de dia da semana, validação que
/// exige ao menos um dia e o tratamento salvo com os dias escolhidos.
void main() {
  /// Monta o app com um botão que abre o diálogo; o retorno da closure
  /// guarda o tratamento salvo (lido DEPOIS que o diálogo fecha).
  Treatment? saved;
  Future<void> openForm(WidgetTester tester) async {
    saved = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                saved = await showDialog<Treatment>(
                  context: context,
                  builder: (_) => const TreatmentFormDialog(),
                );
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  Future<void> fillBasics(WidgetTester tester) async {
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Buscar medicamento'),
      // Nome fora do catálogo: sem lista de sugestões (ListTile em
      // DecoratedBox dispara asserção conhecida do Flutter 3.47.9).
      'Remédio ZZ',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Dosagem'),
      '15MG',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Apresentação'),
      'comprimido',
    );
    await tester.pumpAndSettle();
  }

  Future<void> selectWeeklyFrequency(WidgetTester tester) async {
    await tester.tap(find.text('Todos os dias'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Semanal').last);
    await tester.pumpAndSettle();
  }

  testWidgets('frequência Semenal mostra os sete dias para escolher',
      (tester) async {
    await openForm(tester);

    // Antes de escolher, os dias não aparecem.
    expect(find.text('Seg'), findsNothing);

    await selectWeeklyFrequency(tester);

    expect(find.text('Seg'), findsOneWidget);
    expect(find.text('Qua'), findsOneWidget);
    expect(find.text('Sex'), findsOneWidget);
    expect(find.text('Sáb'), findsOneWidget);
    expect(find.text('Dom'), findsOneWidget);
  });

  testWidgets('salvar semanal sem dia nenhum é barrado com aviso',
      (tester) async {
    await openForm(tester);
    await fillBasics(tester);
    await selectWeeklyFrequency(tester);

    await tester.tap(find.text('Salvar'));
    await tester.pump();

    // "1x por semana" não diz qual dia: sem escolha, sem salvar.
    expect(find.text('Escolha pelo menos um dia da semana.'), findsOneWidget);
  });

  testWidgets('semanal com dia escolhido salva o tratamento com os dias',
      (tester) async {
    await openForm(tester);
    await fillBasics(tester);
    await selectWeeklyFrequency(tester);
    // O formulário é longo: o chip pode estar fora da área visível.
    await tester.ensureVisible(find.text('Sáb'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sáb'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Salvar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.frequency, TreatmentFrequency.weekly);
    expect(saved!.weekdays, [DateTime.saturday]);
  });

  testWidgets('trocar de semanal para diário não carrega dias', (tester) async {
    await openForm(tester);
    await fillBasics(tester);
    await selectWeeklyFrequency(tester);
    await tester.ensureVisible(find.text('Sáb'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sáb'));
    await tester.pumpAndSettle();
    // Volta para diário: os dias escolhidos não vazam para o tratamento.
    await tester.ensureVisible(find.text('Semanal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Semanal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Todos os dias').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(saved!.frequency, TreatmentFrequency.daily);
    expect(saved!.weekdays, isEmpty);
  });
}
