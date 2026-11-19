import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'package:remedios_app_flutter/core/lab_values.dart';
import 'package:remedios_app_flutter/models/lab_result.dart';
import 'package:remedios_app_flutter/providers/lab_result_provider.dart';
import 'package:remedios_app_flutter/screens/lab_results_screen.dart';
import 'package:remedios_app_flutter/services/database_service.dart';

import '../database_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LabResultProvider labs;

  setUp(() async {
    await initializeDateFormatting('pt_BR');
    await setupTestDatabase();
    labs = LabResultProvider();
    await labs.initialize();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
  });

  Widget host() {
    return ChangeNotifierProvider.value(
      value: labs,
      child: const MaterialApp(home: LabResultsScreen()),
    );
  }

  LabValue glicemia(double value, String flag) {
    return LabValue(
      examName: 'Glicemia',
      valueText: formatLabNumber(value),
      numericValue: value,
      unit: 'mg/dL',
      referenceLow: 70,
      referenceHigh: 99,
      referenceText: '70 - 99',
      flag: flag,
    );
  }

  testWidgets('estado vazio mostra as duas chamadas de ação', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('Nenhum laudo registrado'), findsOneWidget);
    expect(find.text('Digitar manualmente'), findsOneWidget);
    expect(find.text('Ler foto com IA'), findsOneWidget);
  });

  testWidgets('histórico lista laudos com flags e resumo', (tester) async {
    await tester.runAsync(() async {
      await labs.saveResult(
        LabResult(
          id: 'l1',
          date: DateTime(2026, 3, 12),
          labName: 'Lab Central',
          values: [glicemia(115, 'high'), glicemia(90, 'normal')],
          notes: 'Coleta em jejum',
        ),
      );
      await labs.initialize();
    });

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('12/03/2026'), findsOneWidget);
    expect(find.text('Lab Central'), findsOneWidget);
    expect(find.text('Glicemia'), findsNWidgets(2));
    expect(find.text('115 mg/dL'), findsOneWidget);
    expect(find.text('90 mg/dL'), findsOneWidget);
    expect(find.text('acima'), findsOneWidget);
    expect(find.text('na faixa'), findsOneWidget);
    expect(find.text('Coleta em jejum'), findsOneWidget);
    expect(find.text('Histórico'), findsOneWidget);
  });

  testWidgets('seção Evolução aparece quando há marcador repetido', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await labs.saveResult(
        LabResult(
          id: 'l1',
          date: DateTime(2026, 1, 10),
          values: [glicemia(95, 'normal')],
        ),
      );
      await labs.saveResult(
        LabResult(
          id: 'l2',
          date: DateTime(2026, 3, 1),
          values: [glicemia(110, 'high')],
        ),
      );
      await labs.initialize();
    });

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    // A seção Evolução vive abaixo da viewport (slivers lazy): rola até ela.
    await tester.scrollUntilVisible(
      find.text('Evolução'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Evolução'), findsOneWidget);
    expect(find.text('95 → 110 mg/dL (subiu ~16%)'), findsOneWidget);
    expect(find.text('entre 10/01/2026 e 01/03/2026'), findsOneWidget);
  });
}
