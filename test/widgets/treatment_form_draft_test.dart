import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:remedios_app_flutter/models/treatment.dart';
import 'package:remedios_app_flutter/models/treatment_draft.dart';
import 'package:remedios_app_flutter/widgets/treatment_form_dialog.dart';

void main() {
  Widget buildSubject(TreatmentDraft draft) {
    return MaterialApp(
      home: Scaffold(body: TreatmentFormDialog(draft: draft)),
    );
  }

  testWidgets('rascunho da receita preenche o formulário para conferência',
      (tester) async {
    final draft = TreatmentDraft(
      name: 'DIPIRONA',
      dosage: '500MG',
      presentation: 'comprimido',
      instructions: 'Tomar 1 comprimido a cada 8 horas por 5 dias',
      doseTimes: const [
        DoseTime(hour: 0, minute: 0),
        DoseTime(hour: 8, minute: 0),
        DoseTime(hour: 16, minute: 0),
      ],
    );

    await tester.pumpWidget(buildSubject(draft));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'DIPIRONA'), findsOneWidget);
    expect(find.widgetWithText(Chip, '08:00'), findsOneWidget);
    expect(find.widgetWithText(Chip, '16:00'), findsOneWidget);
    expect(find.widgetWithText(Chip, '00:00'), findsOneWidget);
    // O título continua "NOVO tratamento": o rascunho não é um tratamento salvo.
    expect(find.text('Novo tratamento'), findsOneWidget);
  });

  testWidgets('rascunho sem horários mantém o 08:00 padrão', (tester) async {
    const draft = TreatmentDraft(name: 'LOSARTANA');

    await tester.pumpWidget(buildSubject(draft));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(Chip, '08:00'), findsOneWidget);
    expect(find.widgetWithText(Chip, '12:00'), findsNothing);
  });
}
