import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:remedios_app_flutter/widgets/treatment_form_dialog.dart';

void main() {
  Widget buildSubject() {
    return const MaterialApp(
      home: Scaffold(body: TreatmentFormDialog()),
    );
  }

  testWidgets('renders interval and routine preset chips', (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ActionChip, 'A cada 8h'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'A cada 12h'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Café 08:00'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Almoço 12:00'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Janta 19:00'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Dormir 22:00'), findsOneWidget);
  });

  testWidgets('tapping the lunch preset adds 12:00 to the dose-time list',
      (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    // New treatment starts with 08:00 only.
    expect(find.widgetWithText(Chip, '12:00'), findsNothing);

    await tester.tap(find.widgetWithText(ActionChip, 'Almoço 12:00'));
    await tester.pump();

    expect(find.widgetWithText(Chip, '12:00'), findsOneWidget);
  });

  testWidgets('tapping a routine preset twice toggles the time off',
      (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ActionChip, 'Almoço 12:00'));
    await tester.pump();
    expect(find.widgetWithText(Chip, '12:00'), findsOneWidget);

    await tester.tap(find.widgetWithText(ActionChip, 'Almoço 12:00'));
    await tester.pump();
    expect(find.widgetWithText(Chip, '12:00'), findsNothing);
  });

  testWidgets('tapping a routine preset for the pre-added time removes it',
      (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    // 08:00 is pre-added for a new treatment: the toggle removes it instead
    // of duplicating.
    expect(find.widgetWithText(Chip, '08:00'), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, 'Café 08:00'));
    await tester.pump();
    expect(find.widgetWithText(Chip, '08:00'), findsNothing);
  });

  testWidgets('added times stay sorted in the dose-time list', (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ActionChip, 'Janta 19:00'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ActionChip, 'Almoço 12:00'));
    await tester.pump();

    final order = tester
        .widgetList<Chip>(find.byType(Chip))
        .map((chip) => (chip.label as Text).data)
        .toList();
    expect(order, ['08:00', '12:00', '19:00']);
  });

  testWidgets('shows a preview of the upcoming doses', (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    // Novo tratamento já vem com 08:00: a prévia existe e usa o rótulo.
    expect(find.textContaining('Próximas doses:'), findsOneWidget);
  });
}
