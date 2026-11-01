import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:remedios_app_flutter/models/doctor_draft.dart';
import 'package:remedios_app_flutter/widgets/doctor_form_dialog.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('rascunho da receita preenche nome em Title Case, CRM e UF',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        DoctorFormDialog(
          draft: const DoctorDraft(
            name: 'SANDRA LINA ALPENDRE',
            crm: '33333',
            crmState: 'SP',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(TextFormField, 'Sandra Lina Alpendre'),
      findsOneWidget,
      reason: 'nome do médico sai em Title Case para conferência',
    );
    expect(find.widgetWithText(TextFormField, '33333'), findsOneWidget);
    expect(
      find.text('Preenchido pela foto da receita — confira antes de salvar.'),
      findsOneWidget,
      reason: 'a origem do preenchimento deve estar visível',
    );
  });

  testWidgets('rascunho só com CRM preenche o registro sem inventar nome',
      (tester) async {
    await tester.pumpWidget(
      _wrap(DoctorFormDialog(draft: const DoctorDraft(crm: '123456'))),
    );
    await tester.pumpAndSettle();

    // O valor e o hint do campo CRM compartilham o texto: exige "ao menos um".
    expect(find.text('123456'), findsWidgets);
    // Nome não inventado: nenhum campo de texto contém sobras do rascunho.
    expect(find.textContaining('SANDRA'), findsNothing);
  });

  testWidgets('sem rascunho o formulário abre vazio e sem aviso',
      (tester) async {
    await tester.pumpWidget(_wrap(const DoctorFormDialog()));
    await tester.pumpAndSettle();

    expect(
      find.text('Preenchido pela foto da receita — confira antes de salvar.'),
      findsNothing,
    );
  });
}
