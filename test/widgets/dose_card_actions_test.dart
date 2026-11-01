import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:remedios_app_flutter/models/dose_event.dart';
import 'package:remedios_app_flutter/models/treatment.dart';
import 'package:remedios_app_flutter/screens/today_screen.dart';

Treatment _treatment() => Treatment(
      id: 't1',
      name: 'TRAMAL 100MG',
      dosage: '100MG',
      presentation: 'cápsula',
      instructions: '12/12 horas',
      startDate: DateTime(2026, 10, 31),
      endDate: null,
      frequency: TreatmentFrequency.daily,
      doseTimes: [DoseTime(hour: 8, minute: 0)],
      stock: null,
      refillThreshold: null,
    );

DoseEvent _event(DoseStatus status) => DoseEvent(
      id: 'e1',
      treatmentId: 't1',
      scheduledAt: DateTime(2026, 10, 31, 8),
      status: status,
    );

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('dose pendente mostra botões Tomei e Pular direto no card',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        DoseCard(
          event: _event(DoseStatus.pending),
          treatment: _treatment(),
          onStatusChanged: (_) {},
        ),
      ),
    );

    expect(find.text('Tomei'), findsOneWidget);
    expect(find.text('Pular'), findsOneWidget);
    // O menu de três pontinhos não existe mais: ação é um toque só.
    expect(find.byType(PopupMenuButton<DoseStatus>), findsNothing);
  });

  testWidgets('tocar em Tomei marca a dose como tomada', (tester) async {
    var received = <DoseStatus>[];
    await tester.pumpWidget(
      _wrap(
        DoseCard(
          event: _event(DoseStatus.pending),
          treatment: _treatment(),
          onStatusChanged: received.add,
        ),
      ),
    );

    await tester.tap(find.text('Tomei'));
    await tester.pump();

    expect(received, [DoseStatus.taken]);
  });

  testWidgets('tocar em Pular marca a dose como pulada', (tester) async {
    var received = <DoseStatus>[];
    await tester.pumpWidget(
      _wrap(
        DoseCard(
          event: _event(DoseStatus.pending),
          treatment: _treatment(),
          onStatusChanged: received.add,
        ),
      ),
    );

    await tester.tap(find.text('Pular'));
    await tester.pump();

    expect(received, [DoseStatus.skipped]);
  });

  testWidgets('dose já tomada mostra o check e não repete as ações',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        DoseCard(
          event: _event(DoseStatus.taken),
          treatment: _treatment(),
          onStatusChanged: (_) {},
        ),
      ),
    );

    expect(find.text('Tomei'), findsNothing);
    expect(find.text('Pular'), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('dose pulada mostra o ícone de pulada e não repete as ações',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        DoseCard(
          event: _event(DoseStatus.skipped),
          treatment: _treatment(),
          onStatusChanged: (_) {},
        ),
      ),
    );

    expect(find.text('Tomei'), findsNothing);
    expect(find.text('Pular'), findsNothing);
    // Ícone aparece no selo e na borda do card (design de dose resolvida).
    expect(find.byIcon(Icons.remove_circle_outline), findsNWidgets(2));
  });
}
