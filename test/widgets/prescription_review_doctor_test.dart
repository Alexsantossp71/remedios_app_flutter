import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:remedios_app_flutter/screens/prescription_review_screen.dart';
import 'package:remedios_app_flutter/services/prescription_reader_service.dart';

/// A conferência mostra quem assinou a receita: o médico lido pelo OCR
/// aparece com nome/CRM editáveis, marcado por padrão — desmarcar é a
/// exceção. "Continuar" devolve o médico confirmado no outcome.
void main() {
  final receitaComMedico = const PrescriptionReadResult(
    medicamentos: [
      PrescriptionMedication(nome: 'LOSARTANA', horarios: ['08:00']),
    ],
    rawText: 'LOSARTANA',
    medico: PrescriptionDoctor(nome: 'DR. CARLOS', crm: '123456', uf: 'SP'),
  );

  /// Abre a conferência e devolve o "botão" de continuar + captura do
  /// outcome — os testes agem nos campos antes de continuar.
  Future<PrescriptionReviewOutcome? Function()> openReview(
    WidgetTester tester,
    PrescriptionReadResult result,
  ) async {
    PrescriptionReviewOutcome? outcome;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              outcome = await Navigator.of(context)
                  .push<PrescriptionReviewOutcome>(
                    MaterialPageRoute<PrescriptionReviewOutcome>(
                      builder: (_) => Scaffold(
                        body: PrescriptionReviewScreen(
                          result: result,
                          catalogFuture: Future.value(const []),
                        ),
                      ),
                    ),
                  );
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    return () => outcome;
  }

  testWidgets('médico lido da receita abre no card para conferência', (
    tester,
  ) async {
    final capture = await openReview(tester, receitaComMedico);

    // Preenchido e confirmado por padrão: registrar quem assinou é o
    // caminho fácil, sem toque extra.
    expect(find.text('Registrar quem receitou'), findsOneWidget);
    expect(find.text('DR. CARLOS'), findsOneWidget);
    // Hint convive com o valor preenchido na árvore do InputDecorator.
    expect(find.text('123456'), findsWidgets);
    expect(find.text('SP'), findsWidgets);

    await tester.tap(find.text('Continuar com 1 tratamento(s)'));
    await tester.pumpAndSettle();

    final outcome = capture();
    expect(outcome, isNotNull);
    expect(outcome!.medico, isNotNull);
    expect(outcome.medico!.nome, 'DR. CARLOS');
    expect(outcome.medico!.crm, '123456');
    expect(outcome.medico!.uf, 'SP');
    expect(outcome.drafts, hasLength(1));
  });

  testWidgets('edição do médico na conferência segue para o outcome', (
    tester,
  ) async {
    final capture = await openReview(
      tester,
      const PrescriptionReadResult(
        medicamentos: [
          PrescriptionMedication(nome: 'LOSARTANA', horarios: ['08:00']),
        ],
        rawText: 'LOSARTANA',
        medico: PrescriptionDoctor(nome: 'DR. CQRLOS', crm: '123456'),
      ),
    );

    // Corrige a grafia lida por OCR antes de continuar.
    await tester.enterText(
      find.widgetWithText(TextField, 'Médico que receitou'),
      'Dr. Carlos Almeida',
    );
    await tester.enterText(find.widgetWithText(TextField, 'UF'), 'SP');
    await tester.tap(find.text('Continuar com 1 tratamento(s)'));
    await tester.pumpAndSettle();

    final outcome = capture()!;
    expect(outcome.medico, isNotNull);
    expect(outcome.medico!.nome, 'Dr. Carlos Almeida');
    expect(outcome.medico!.uf, 'SP');
  });

  testWidgets('desmarcar o médico devolve outcome sem prescritor', (
    tester,
  ) async {
    final capture = await openReview(tester, receitaComMedico);

    // O primeiro checkbox da tela é o do card de médico (os das
    // medicamentos vêm depois).
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar com 1 tratamento(s)'));
    await tester.pumpAndSettle();

    // O usuário decidiu não registrar: rascunhos seguem, médico não.
    final outcome = capture()!;
    expect(outcome.medico, isNull);
    expect(outcome.drafts, hasLength(1));
  });

  testWidgets('receita sem médico não mostra o card', (tester) async {
    final capture = await openReview(
      tester,
      const PrescriptionReadResult(
        medicamentos: [
          PrescriptionMedication(nome: 'DIPIRONA', horarios: ['08:00']),
        ],
        rawText: 'DIPIRONA',
      ),
    );

    expect(find.text('Registrar quem receitou'), findsNothing);

    await tester.tap(find.text('Continuar com 1 tratamento(s)'));
    await tester.pumpAndSettle();
    expect(capture()!.medico, isNull);
  });
}
