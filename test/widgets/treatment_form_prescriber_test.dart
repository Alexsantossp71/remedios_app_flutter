import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:remedios_app_flutter/models/doctor.dart';
import 'package:remedios_app_flutter/models/prescription_record.dart';
import 'package:remedios_app_flutter/models/treatment.dart';
import 'package:remedios_app_flutter/models/treatment_draft.dart';
import 'package:remedios_app_flutter/services/prescription_reader_service.dart';
import 'package:remedios_app_flutter/widgets/treatment_form_dialog.dart';

void main() {
  /// Abre o formulário (rascunho ou manual) já no passo 3 — os testes
  /// abaixo só olham a seção "Quem receitou".
  Future<void> openForm(
    WidgetTester tester, {
    TreatmentDraft? draft,
    PrescriptionDoctor? prescriptionDoctor,
    List<Doctor> doctorCatalog = const [],
    List<PrescriptionRecord> prescriptionHistory = const [],
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TreatmentFormDialog(
            draft: draft,
            prescriptionDoctor: prescriptionDoctor,
            doctorCatalog: doctorCatalog,
            prescriptionHistory: prescriptionHistory,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Rascunho preenche o passo 1; sem rascunho, digita o nome do remédio.
    if (draft == null) {
      await tester.enterText(find.byType(TextField).first, 'LOSARTANA');
    }
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
  }

  testWidgets('passo 3 tem a seção "Quem receitou" com data da receita', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: TreatmentFormDialog())),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'LOSARTANA');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(find.text('Quem receitou'), findsOneWidget);
    expect(
      find.text(
        'Fica no registro do tratamento: quem prescreveu e em que dia.',
      ),
      findsOneWidget,
    );
    expect(find.text('Médico que receitou'), findsOneWidget);
    expect(find.textContaining('Receita emitida em'), findsOneWidget);
  });

  testWidgets('médico digitado vira registro no tratamento salvo', (
    tester,
  ) async {
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
                    name: 'LOSARTANA',
                    dosage: '50MG',
                    presentation: 'comprimido',
                    doseTimes: [DoseTime(hour: 8, minute: 0)],
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
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Médico que receitou'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Médico que receitou'),
      'Dr. Carlos Almeida',
    );
    await tester.ensureVisible(find.text('CRM (opcional)'));
    await tester.enterText(
      find.widgetWithText(TextField, 'CRM (opcional)'),
      '123456',
    );
    await tester.enterText(find.widgetWithText(TextField, 'UF'), 'SP');

    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    final result = saved!;
    expect(result.hasPrescriber, isTrue);
    expect(result.prescriberName, 'Dr. Carlos Almeida');
    expect(result.prescriberCrm, '123456');
    expect(result.prescriberCrmState, 'SP');
    expect(result.prescriberCrmLabel, 'CRM 123456/SP');
    expect(result.prescribedOn, isNotNull);
  });

  testWidgets('médico lido da receita abre preenchido para conferência', (
    tester,
  ) async {
    await openForm(
      tester,
      draft: const TreatmentDraft(
        name: 'LOSARTANA',
        dosage: '50MG',
        presentation: 'comprimido',
        doseTimes: [DoseTime(hour: 8, minute: 0)],
      ),
      prescriptionDoctor: const PrescriptionDoctor(
        nome: 'DR. CARLOS ALMEIDA',
        crm: '123456',
        uf: 'SP',
      ),
    );

    expect(find.text('DR. CARLOS ALMEIDA'), findsOneWidget);
    // O hint do campo convive com o valor preenchido na árvore.
    expect(find.text('123456'), findsWidgets);
    expect(find.text('SP'), findsWidgets);
  });

  testWidgets('sem médico trava o salvar com aviso claro', (tester) async {
    await openForm(
      tester,
      draft: const TreatmentDraft(
        name: 'LOSARTANA',
        dosage: '50MG',
        presentation: 'comprimido',
        doseTimes: [DoseTime(hour: 8, minute: 0)],
      ),
    );

    await tester.ensureVisible(find.text('CRM (opcional)'));
    await tester.enterText(
      find.widgetWithText(TextField, 'CRM (opcional)'),
      '123456',
    );
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    // Não salvou: o passo continua na tela com o aviso — "quem receitou"
    // é obrigatório, CRM sozinho não basta.
    expect(find.text('Informe o médico que receitou.'), findsOneWidget);
    expect(find.text('Salvar'), findsOneWidget);
  });

  testWidgets('catálogo vazio mostra o cadastro inline de médico', (
    tester,
  ) async {
    await openForm(
      tester,
      draft: const TreatmentDraft(
        name: 'LOSARTANA',
        dosage: '50MG',
        presentation: 'comprimido',
        doseTimes: [DoseTime(hour: 8, minute: 0)],
      ),
    );

    // Sem catálogo, a seção obrigatória não é beco sem saída: traz o
    // banner com o botão que cadastra o médico ali mesmo.
    expect(
      find.text(
        'Nenhum médico cadastrado. O médico é obrigatório — cadastre aqui '
        'para continuar.',
      ),
      findsOneWidget,
    );
    expect(find.text('Cadastrar médico'), findsOneWidget);
  });

  testWidgets('médico do catálogo preenche nome e CRM com um toque', (
    tester,
  ) async {
    await openForm(
      tester,
      draft: const TreatmentDraft(
        name: 'LOSARTANA',
        dosage: '50MG',
        presentation: 'comprimido',
        doseTimes: [DoseTime(hour: 8, minute: 0)],
      ),
      doctorCatalog: const [
        Doctor(
          id: 'doc-1',
          name: 'Dra. Ana Prado',
          crm: '654321',
          crmState: 'SP',
        ),
      ],
    );

    await tester.ensureVisible(find.text('Do catálogo'));
    await tester.tap(find.text('Do catálogo'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dra. Ana Prado · CRM 654321/SP').last);
    await tester.pumpAndSettle();

    expect(find.text('Dra. Ana Prado'), findsOneWidget);
    expect(find.text('654321'), findsOneWidget);
    // Hint 'SP' + valor 'SP' coexistem na árvore do InputDecorator.
    expect(find.text('SP'), findsWidgets);
  });

  testWidgets('histórico de receitas fica à disposição na edição', (
    tester,
  ) async {
    Treatment? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await showDialog<Treatment>(
                context: context,
                builder: (_) => TreatmentFormDialog(
                  initialTreatment: Treatment(
                    id: 'treat-1',
                    name: 'Metotrexato',
                    dosage: '15MG',
                    presentation: 'Comprimido',
                    instructions: '',
                    startDate: DateTime(2026, 11, 1),
                    endDate: null,
                    frequency: TreatmentFrequency.weekly,
                    doseTimes: const [DoseTime(hour: 8, minute: 0)],
                    weekdays: const [DateTime.saturday],
                    stock: 4,
                    refillThreshold: 1,
                    prescriberName: 'Dr. Carlos Almeida',
                    prescriberCrm: '123456',
                    prescriberCrmState: 'SP',
                    prescribedOn: DateTime(2026, 11, 15),
                  ),
                  prescriptionHistory: [
                    PrescriptionRecord(
                      id: 'rec-old',
                      treatmentId: 'treat-1',
                      doctorName: 'Dra. Ana Prado',
                      doctorCrm: '654321',
                      doctorCrmState: 'SP',
                      prescribedOn: DateTime(2026, 2, 10),
                      source: PrescriptionSource.prescriptionPhoto,
                      createdAt: DateTime(2026, 2, 10, 9),
                    ),
                  ],
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
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    // O prescritor atual abre preenchido no formulário.
    expect(find.text('Dr. Carlos Almeida'), findsOneWidget);

    // E a receita anterior fica no histórico, expansível.
    await tester.ensureVisible(find.text('Histórico de receitas (1)'));
    expect(find.textContaining('Dra. Ana Prado'), findsNothing);
    await tester.tap(find.text('Histórico de receitas (1)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Dra. Ana Prado'), findsOneWidget);
    expect(find.textContaining('Receita em 10/02/2026'), findsOneWidget);

    expect(saved, isNull);
  });
}
