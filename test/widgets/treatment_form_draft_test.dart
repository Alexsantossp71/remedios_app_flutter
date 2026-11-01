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

  testWidgets('frequência lida da receita abre pré-selecionada para conferência',
      (tester) async {
    const draft = TreatmentDraft(
      name: 'CALCITRIOL',
      doseTimes: [DoseTime(hour: 8, minute: 0)],
      frequency: TreatmentFrequency.everyOtherDay,
    );

    await tester.pumpWidget(buildSubject(draft));
    await tester.pumpAndSettle();

    // O dropdown abre já com "Dia sim, dia não": o usuário VÊ a frequência
    // que a leitura inferiu e pode trocar antes de salvar.
    expect(find.text('Dia sim, dia não'), findsOneWidget);
  });

  testWidgets('rascunho semanal abre com os dias da receita marcados',
      (tester) async {
    Treatment? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await showDialog<Treatment>(
                context: context,
                builder: (_) => const TreatmentFormDialog(
                  draft: TreatmentDraft(
                    name: 'METOTREXATO',
                    dosage: '15MG',
                    presentation: 'comprimido',
                    doseTimes: [DoseTime(hour: 8, minute: 0)],
                    frequency: TreatmentFrequency.weekly,
                    weekdays: [DateTime.saturday],
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

    // "1x por semana aos sábados": frequência e dia vêm da receita, visíveis.
    expect(find.text('Semanal'), findsOneWidget);
    final sabadoChip =
        tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'Sáb'));
    expect(sabadoChip.selected, isTrue);
    final segundaChip =
        tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'Seg'));
    expect(segundaChip.selected, isFalse);

    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.frequency, TreatmentFrequency.weekly);
    expect(saved!.weekdays, [DateTime.saturday]);
  });
}
