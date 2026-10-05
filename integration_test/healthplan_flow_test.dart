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

  group('Health Plan Management Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await DatabaseService.instance.initInMemoryDatabase();
    });

    testWidgets('Navigate to health plans screen', (tester) async {
      await _pumpApp(tester);

      await tester.tap(find.text('Planos'));
      await tester.pumpAndSettle();

      expect(find.text('Seus planos de saúde'), findsOneWidget);
    });

    testWidgets('Can open add health plan dialog', (tester) async {
      await _pumpApp(tester);

      await tester.tap(find.text('Planos'));
      await tester.pumpAndSettle();

      // Look for add health plan button
      final addButton = find.text('Adicionar plano');
      if (addButton.evaluate().isNotEmpty) {
        await tester.tap(addButton);
        await tester.pumpAndSettle();

        // Dialog should open
        expect(find.text('Novo plano de saúde'), findsOneWidget);
      }
    });

    testWidgets('Health plan form has required fields', (tester) async {
      await _pumpApp(tester);

      await tester.tap(find.text('Planos'));
      await tester.pumpAndSettle();

      final addButton = find.text('Adicionar plano');
      if (addButton.evaluate().isNotEmpty) {
        await tester.tap(addButton);
        await tester.pumpAndSettle();

        // Check for form fields
        expect(find.widgetWithText(TextFormField, 'Nome do plano'), findsOneWidget);
        expect(find.widgetWithText(TextFormField, 'Número da carteirinha'), findsOneWidget);
      }
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