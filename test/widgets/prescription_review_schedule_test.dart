import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:remedios_app_flutter/models/treatment.dart';
import 'package:remedios_app_flutter/models/treatment_draft.dart';
import 'package:remedios_app_flutter/screens/prescription_review_screen.dart';
import 'package:remedios_app_flutter/services/prescription_reader_service.dart';

/// A conferência vira agendamento: chips geradores de horários (intervalo e
/// "Nx ao dia") e frequência lida da receita ("dia sim, dia não") seguindo no
/// rascunho. Um toque substitui a montagem manual de cada horário.
void main() {
  Future<void> openReview(
    WidgetTester tester,
    PrescriptionReadResult result,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrescriptionReviewScreen(
            result: result,
            catalogFuture: Future.value(const []),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Confirma o diálogo "Horário da primeira dose" sem mudar o horário.
  Future<void> confirmFirstDose(WidgetTester tester) async {
    expect(find.text('Horário da primeira dose'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  testWidgets('intervalo da receita gera o dia inteiro a partir da 1ª dose',
      (tester) async {
    await openReview(
      tester,
      PrescriptionReadResult(
        medicamentos: const [
          PrescriptionMedication(
            nome: 'AZITROMICINA',
            intervaloHoras: 6,
            horarios: ['08:00'],
          ),
        ],
        rawText: 'AZITROMICINA',
      ),
    );

    // O intervalo lido vira chip marcado como "(receita)"; os de rotina
    // (8/12/24h) continuam disponíveis.
    expect(find.text('A cada 6h (receita)'), findsOneWidget);
    expect(find.text('A cada 8h'), findsOneWidget);

    await tester.tap(find.text('A cada 6h (receita)'));
    await tester.pump();
    await confirmFirstDose(tester);

    // 6 em 6 horas a partir das 08:00 — o dia fecha com a dose 02:00.
    expect(find.widgetWithText(Chip, '08:00'), findsOneWidget);
    expect(find.widgetWithText(Chip, '14:00'), findsOneWidget);
    expect(find.widgetWithText(Chip, '20:00'), findsOneWidget);
    expect(find.widgetWithText(Chip, '02:00'), findsOneWidget);
  });

  testWidgets('âncora segue a 1ª dose escolhida, não o relógio',
      (tester) async {
    await openReview(
      tester,
      PrescriptionReadResult(
        medicamentos: const [
          PrescriptionMedication(
            nome: 'LOSARTANA',
            intervaloHoras: 12,
            horarios: ['22:00'],
          ),
        ],
        rawText: 'LOSARTANA',
      ),
    );

    await tester.tap(find.text('A cada 12h (receita)'));
    await tester.pump();
    await confirmFirstDose(tester);

    // 1ª toma às 22:00 → 10:00 e 22:00, inclusive a que cruza a meia-noite.
    expect(find.widgetWithText(Chip, '10:00'), findsOneWidget);
    expect(find.widgetWithText(Chip, '22:00'), findsOneWidget);
    expect(find.widgetWithText(Chip, '08:00'), findsNothing);
  });

  testWidgets('"Distribuir Nx ao dia" aparece quando a receita conta vezes',
      (tester) async {
    await openReview(
      tester,
      PrescriptionReadResult(
        medicamentos: const [
          PrescriptionMedication(
            nome: 'SERTRALINA',
            vezesAoDia: 3,
            horarios: ['08:00'],
          ),
        ],
        rawText: 'SERTRALINA',
      ),
    );

    expect(find.text('Distribuir 3x ao dia'), findsOneWidget);

    await tester.tap(find.text('Distribuir 3x ao dia'));
    await tester.pump();
    await confirmFirstDose(tester);

    expect(find.widgetWithText(Chip, '08:00'), findsOneWidget);
    expect(find.widgetWithText(Chip, '16:00'), findsOneWidget);
    expect(find.widgetWithText(Chip, '00:00'), findsOneWidget);
  });

  testWidgets('"dia sim, dia não" lido da receita segue no rascunho',
      (tester) async {
    final popped = <List<TreatmentDraft>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final drafts = await Navigator.of(context).push<List<TreatmentDraft>>(
                MaterialPageRoute<List<TreatmentDraft>>(
                  builder: (_) => Scaffold(
                    body: PrescriptionReviewScreen(
                      result: const PrescriptionReadResult(
                        medicamentos: [
                          PrescriptionMedication(
                            nome: 'CALCITRIOL',
                            horarios: ['08:00'],
                            diasAlternados: true,
                          ),
                        ],
                        rawText: 'CALCITRIOL',
                      ),
                      catalogFuture: Future.value(const []),
                    ),
                  ),
                ),
              );
              if (drafts != null) popped.add(drafts);
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continuar com 1 tratamento(s)'));
    await tester.pumpAndSettle();

    expect(popped, hasLength(1));
    final draft = popped.single.single;
    expect(draft.name, 'CALCITRIOL');
    expect(draft.frequency, TreatmentFrequency.everyOtherDay);
  });

  testWidgets('receita sem frequência especial deixa o rascunho sem palpite',
      (tester) async {
    final popped = <List<TreatmentDraft>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final drafts = await Navigator.of(context).push<List<TreatmentDraft>>(
                MaterialPageRoute<List<TreatmentDraft>>(
                  builder: (_) => Scaffold(
                    body: PrescriptionReviewScreen(
                      result: const PrescriptionReadResult(
                        medicamentos: [
                          PrescriptionMedication(
                            nome: 'DIPIRONA',
                            intervaloHoras: 8,
                            horarios: ['08:00', '16:00', '00:00'],
                          ),
                        ],
                        rawText: 'DIPIRONA',
                      ),
                      catalogFuture: Future.value(const []),
                    ),
                  ),
                ),
              );
              if (drafts != null) popped.add(drafts);
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continuar com 1 tratamento(s)'));
    await tester.pumpAndSettle();

    expect(popped.single.single.frequency, isNull);
  });
}
