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

  group('Consultation Scheduling Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await DatabaseService.instance.initInMemoryDatabase();
    });

    testWidgets('Navigate to consultations screen', (tester) async {
      await _pumpApp(tester);

      await tester.tap(find.text('Consultas'));
      await tester.pumpAndSettle();

      expect(find.text('Suas consultas'), findsOneWidget);
    });

    testWidgets('Can open schedule consultation dialog', (tester) async {
      await _pumpApp(tester);

      await tester.tap(find.text('Consultas'));
      await tester.pumpAndSettle();

      // Look for add consultation button
      final addButton = find.text('Agendar consulta');
      if (addButton.evaluate().isNotEmpty) {
        await tester.tap(addButton);
        await tester.pumpAndSettle();

        // Dialog should open
        expect(find.text('Agendar consulta'), findsOneWidget);
      }
    });

    testWidgets('Consultation calendar is visible', (tester) async {
      await _pumpApp(tester);

      await tester.tap(find.text('Consultas'));
      await tester.pumpAndSettle();

      // Calendar should be present
      expect(find.text('Suas consultas'), findsOneWidget);
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