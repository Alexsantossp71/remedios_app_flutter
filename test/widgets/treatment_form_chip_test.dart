import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:remedios_app_flutter/widgets/treatment_form_dialog.dart';

void main() {
  Widget buildSubject() {
    return const MaterialApp(
      home: Scaffold(body: TreatmentFormDialog()),
    );
  }

  testWidgets('renders quick-pick chips for 08:00, 12:00 and 18:00',
      (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ActionChip, '08:00'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, '12:00'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, '18:00'), findsOneWidget);
  });

  testWidgets('tapping 12:00 chip adds that time to the dose-time list',
      (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    // New treatment starts with 08:00 only; 12:00 must not be a dose Chip yet.
    expect(find.widgetWithText(Chip, '12:00'), findsNothing);

    await tester.tap(find.widgetWithText(ActionChip, '12:00'));
    await tester.pump();

    expect(find.widgetWithText(Chip, '12:00'), findsOneWidget);
  });

  testWidgets('tapping a chip for an already-added time does not duplicate it',
      (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    // 08:00 is pre-added for a new treatment.
    expect(find.widgetWithText(Chip, '08:00'), findsOneWidget);

    await tester.tap(find.widgetWithText(ActionChip, '08:00'));
    await tester.pump();

    expect(find.widgetWithText(Chip, '08:00'), findsOneWidget);
  });

  testWidgets('added times stay sorted in the dose-time list', (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ActionChip, '18:00'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ActionChip, '12:00'));
    await tester.pump();

    final order = tester
        .widgetList<Chip>(find.byType(Chip))
        .map((chip) => (chip.label as Text).data)
        .toList();
    expect(order, ['08:00', '12:00', '18:00']);
  });
}
