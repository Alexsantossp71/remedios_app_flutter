import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:remedios_app_flutter/main.dart';
import 'package:remedios_app_flutter/providers/consultation_provider.dart';
import 'package:remedios_app_flutter/providers/doctor_provider.dart';
import 'package:remedios_app_flutter/providers/health_plan_provider.dart';
import 'package:remedios_app_flutter/providers/therapy_provider.dart';
import 'package:remedios_app_flutter/services/database_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Medicine/Treatment Flow Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await DatabaseService.instance.initInMemoryDatabase();
    });

    testWidgets('Navigate to medicines catalog', (tester) async {
      await _pumpApp(tester);

      await tester.tap(find.text('Medicamentos'));
      await tester.pumpAndSettle();

      expect(find.text('Seus medicamentos'), findsOneWidget);
      expect(find.text('Adicionar tratamento'), findsOneWidget);
    });

    testWidgets('Can open add treatment dialog', (tester) async {
      await _pumpApp(tester);

      await tester.tap(find.text('Medicamentos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Adicionar tratamento'));
      await tester.pumpAndSettle();

      // Dialog should open with medicine search
      expect(find.text('Buscar medicamento'), findsOneWidget);
    });

    testWidgets('Can search for medicine in catalog', (tester) async {
      await _pumpApp(tester);

      await tester.tap(find.text('Medicamentos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Adicionar tratamento'));
      await tester.pumpAndSettle();

      // Search for a common medicine
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Buscar medicamento'),
        'Dipirona',
      );
      await tester.pumpAndSettle();

      // Should show search results
      expect(find.textContaining('Dipirona'), findsWidgets);
    });
  });
}

Future<void> _pumpApp(WidgetTester tester) async {
  final therapyProvider = TherapyProvider();
  final doctorProvider = DoctorProvider();
  final consultationProvider = ConsultationProvider();
  final healthPlanProvider = HealthPlanProvider();
  await therapyProvider.initialize();
  await doctorProvider.initialize();
  await consultationProvider.initialize();
  await healthPlanProvider.initialize();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: therapyProvider),
        ChangeNotifierProvider.value(value: doctorProvider),
        ChangeNotifierProvider.value(value: consultationProvider),
        ChangeNotifierProvider.value(value: healthPlanProvider),
      ],
      child: const RemediosApp(),
    ),
  );
  await tester.pumpAndSettle();
}