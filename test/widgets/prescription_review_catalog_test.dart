import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:remedios_app_flutter/models/medicine.dart';
import 'package:remedios_app_flutter/screens/prescription_review_screen.dart';
import 'package:remedios_app_flutter/services/prescription_reader_service.dart';

void main() {
  final fakeCatalog = <Medicine>[
    Medicine(
      name: 'DIPIRONA',
      dosage: '500MG',
      presentation: '500MG CX C/ 10 CPR',
    ),
    Medicine(
      name: 'LOSARTANA POTÁSSICA',
      dosage: '',
      presentation: '50MG CX C/ 30 CPR',
    ),
  ];

  Future<void> openReview(WidgetTester tester, PrescriptionReadResult result) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrescriptionReviewScreen(
            result: result,
            catalogFuture: Future.value(fakeCatalog),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sugere entrada do catálogo para nome lido por OCR',
      (tester) async {
    await openReview(
      tester,
      PrescriptionReadResult(
        medicamentos: const [
          PrescriptionMedication(nome: 'dipiron', horarios: ['08:00']),
        ],
        rawText: 'dipiron',
      ),
    );

    expect(find.textContaining('Catálogo: DIPIRONA'), findsOneWidget);
  });

  testWidgets('aplicar a sugestão corrige grafia e completa campos',
      (tester) async {
    await openReview(
      tester,
      PrescriptionReadResult(
        medicamentos: const [
          PrescriptionMedication(nome: 'dipiron', horarios: ['08:00']),
        ],
        rawText: 'dipiron',
      ),
    );

    await tester.tap(find.textContaining('Catálogo: DIPIRONA'));
    await tester.pump();

    // Nome corrigido para a grafia do catálogo; dosagem completa; a sugestão
    // desaparece porque não sobrou nada a ganhar.
    expect(find.text('DIPIRONA'), findsOneWidget);
    expect(find.text('500MG'), findsOneWidget);
    expect(find.textContaining('Catálogo:'), findsNothing);
  });

  testWidgets('nome já correto sem campos a completar não gera sugestão',
      (tester) async {
    await openReview(
      tester,
      PrescriptionReadResult(
        medicamentos: const [
          PrescriptionMedication(
            nome: 'DIPIRONA',
            dosagem: '500MG',
            apresentacao: 'comprimido',
            horarios: ['08:00'],
          ),
        ],
        rawText: 'DIPIRONA',
      ),
    );

    expect(find.textContaining('Catálogo:'), findsNothing);
  });

  testWidgets('nome correto mas apresentação vazia sugere completar',
      (tester) async {
    await openReview(
      tester,
      PrescriptionReadResult(
        medicamentos: const [
          PrescriptionMedication(
            nome: 'losartana',
            horarios: ['08:00'],
          ),
        ],
        rawText: 'losartana',
      ),
    );

    expect(
      find.textContaining('Catálogo: LOSARTANA POTÁSSICA'),
      findsOneWidget,
    );
  });
}
