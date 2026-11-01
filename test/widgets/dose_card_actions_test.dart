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

/// Cores semânticas do fallback claro de [AppSemanticColors] (usado quando
/// o MaterialApp simples de teste não registra a extensão).
const Color _success = Color(0xFF2E9E6B);
const Color _danger = Color(0xFFD64545);

BorderSide _cardSide(WidgetTester tester) =>
    (tester.widget<Card>(find.byType(Card)).shape as RoundedRectangleBorder)
        .side;

void main() {
  testWidgets(
      'contorno por estado: pendente sutil, tomada borda verde, pulada borda vermelha',
      (tester) async {
    // Pendente: contorno de destaque no azul de ação (não é verde/vermelho).
    await tester.pumpWidget(
      _wrap(
        DoseCard(
          event: _event(DoseStatus.pending),
          treatment: _treatment(),
          onStatusChanged: (_) {},
        ),
      ),
    );
    final pendingSide = _cardSide(tester);
    expect(pendingSide, isNot(BorderSide.none),
        reason: 'dose pendente deve ter contorno de destaque');
    expect(pendingSide.color, isNot(_success));
    expect(pendingSide.color, isNot(_danger));

    // Tomada: o card recebe borda verde.
    await tester.pumpWidget(
      _wrap(
        DoseCard(
          event: _event(DoseStatus.taken),
          treatment: _treatment(),
          onStatusChanged: (_) {},
        ),
      ),
    );
    final takenSide = _cardSide(tester);
    expect(takenSide.color, _success,
        reason: 'dose tomada deve receber borda verde');
    expect(takenSide.width, 2);

    // Pulada: o card recebe borda vermelha.
    await tester.pumpWidget(
      _wrap(
        DoseCard(
          event: _event(DoseStatus.skipped),
          treatment: _treatment(),
          onStatusChanged: (_) {},
        ),
      ),
    );
    final skippedSide = _cardSide(tester);
    expect(skippedSide.color, _danger,
        reason: 'dose pulada deve receber borda vermelha');
    expect(skippedSide.width, 2);
  });

  testWidgets(
      'ações pendentes são botões circulares em coluna: Tomei verde acima de Pular vermelho',
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

    final tomeiFinder = find.widgetWithIcon(IconButton, Icons.check_rounded);
    final pularFinder =
        find.widgetWithIcon(IconButton, Icons.skip_next_rounded);
    expect(tomeiFinder, findsOneWidget);
    expect(pularFinder, findsOneWidget);

    final tomei = tester.widget<IconButton>(tomeiFinder);
    final pular = tester.widget<IconButton>(pularFinder);

    // Verde para Tomei, vermelho para Pular.
    expect(tomei.style?.backgroundColor?.resolve({}), _success);
    expect(pular.style?.backgroundColor?.resolve({}), _danger);

    // Botões circulares.
    expect(tomei.style?.shape?.resolve({}), isA<CircleBorder>());
    expect(pular.style?.shape?.resolve({}), isA<CircleBorder>());

    // Empilhados na mesma linha do medicamento: Tomei acima de Pular.
    final tomeiCenter = tester.getCenter(tomeiFinder);
    final pularCenter = tester.getCenter(pularFinder);
    expect(tomeiCenter.dy, lessThan(pularCenter.dy),
        reason: 'Tomei deve ficar acima de Pular (coluna)');
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

    await tester.tap(find.byTooltip('Tomei'));
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

    await tester.tap(find.byTooltip('Pular'));
    await tester.pump();

    expect(received, [DoseStatus.skipped]);
  });

  testWidgets('dose já tomada mostra o check, borda verde e não repete as ações',
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

    expect(find.byTooltip('Tomei'), findsNothing);
    expect(find.byTooltip('Pular'), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(_cardSide(tester).color, _success);
  });

  testWidgets('dose pulada mostra o ícone, borda vermelha e não repete as ações',
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

    expect(find.byTooltip('Tomei'), findsNothing);
    expect(find.byTooltip('Pular'), findsNothing);
    // Ícone aparece no selo e na borda do card (design de dose resolvida).
    expect(find.byIcon(Icons.remove_circle_outline), findsNWidgets(2));
    expect(_cardSide(tester).color, _danger);
  });
}
