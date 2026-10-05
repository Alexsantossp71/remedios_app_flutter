import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:remedios_app_flutter/main.dart';
import 'package:remedios_app_flutter/providers/consultation_provider.dart';
import 'package:remedios_app_flutter/providers/doctor_provider.dart';
import 'package:remedios_app_flutter/providers/health_plan_provider.dart';
import 'package:remedios_app_flutter/providers/therapy_provider.dart';
import 'package:remedios_app_flutter/providers/user_profile_provider.dart';
import 'package:remedios_app_flutter/services/database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TherapyProvider therapyProvider;
  late DoctorProvider doctorProvider;
  late ConsultationProvider consultationProvider;
  late HealthPlanProvider healthPlanProvider;
  late UserProfileProvider userProfileProvider;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await _resetInMemoryDb();
    // As inicializações ficam fora do corpo de testWidgets: dentro da zona
    // fake do binding o IO real do SQLite nunca completa e o teste trava.
    therapyProvider = TherapyProvider();
    doctorProvider = DoctorProvider();
    consultationProvider = ConsultationProvider();
    healthPlanProvider = HealthPlanProvider();
    userProfileProvider = UserProfileProvider();
    await therapyProvider.initialize();
    await doctorProvider.initialize();
    await consultationProvider.initialize();
    await healthPlanProvider.initialize();
    await userProfileProvider.initialize();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TherapyProvider>.value(value: therapyProvider),
          ChangeNotifierProvider<DoctorProvider>.value(value: doctorProvider),
          ChangeNotifierProvider<ConsultationProvider>.value(
            value: consultationProvider,
          ),
          ChangeNotifierProvider<HealthPlanProvider>.value(
            value: healthPlanProvider,
          ),
          ChangeNotifierProvider<UserProfileProvider>.value(
            value: userProfileProvider,
          ),
        ],
        child: const RemediosApp(),
      ),
    );
    await _pumpFor(tester);
    await _pumpFor(tester);
  }

  testWidgets('App loads with title', (tester) async {
    await pumpApp(tester);

    expect(find.text('Remédio na Hora'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('Doctors catalog is reachable from the main navigation',
      (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Médicos'));
    await _pumpFor(tester);

    expect(find.text('Seus médicos'), findsOneWidget);
    expect(find.text('Seu catálogo começa aqui'), findsOneWidget);
  });

  testWidgets('Can add a doctor with contact and location details',
      (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Médicos'));
    await _pumpFor(tester);
    await tester.tap(find.text('Cadastrar primeiro médico'));
    await _pumpFor(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nome do médico'),
      'Dra. Paula Costa',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Especialidade'),
      'Dermatologia',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'CRM'), '54321');
    await tester.ensureVisible(find.byKey(const ValueKey('crmStateUf')));
    // O teclado sobrepoe o campo e o toque no dropdown não abriria o menu.
    tester.testTextInput.hide();
    await _pumpFor(tester);
    await tester.tap(find.byKey(const ValueKey('crmStateUf')));
    await _pumpFor(tester);
    // O menu do DropdownButtonFormField abre em rota; um segundo toque cobre o
    // caso em que o primeiro caiu enquanto o campo ainda estava animando.
    if (find.text('CE').evaluate().isEmpty) {
      await tester.tap(find.byKey(const ValueKey('crmStateUf')));
      await _pumpFor(tester);
    }
    await tester.tap(find.text('CE').last);
    await _pumpFor(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Telefone'),
      '(21) 99999-0000',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Clínica ou consultório'),
      'Clínica Central',
    );
    await tester.ensureVisible(find.text('Preencher endereço sem CEP'));
    await _pumpFor(tester);
    await tester.tap(find.text('Preencher endereço sem CEP'));
    await _pumpFor(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Rua ou avenida'),
      'Rua das Palmeiras',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Número'), '45');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Cidade'), 'Niterói');
    await tester.ensureVisible(find.byKey(const ValueKey('addressUf')));
    await _pumpFor(tester);
    await tester.tap(find.byKey(const ValueKey('addressUf')));
    await _pumpFor(tester);
    await tester.tap(find.text('CE').last);
    await _pumpFor(tester);
    await tester.ensureVisible(find.text('Cadastrar').last);
    await _pumpFor(tester);
    await tester.tap(find.text('Cadastrar').last);
    await tester.pump();
    // O save grava no SQLite (IO real), que não resolve dentro da zona fake
    // do binding: sem runAsync o notifyListeners chega tarde e o Consumer
    // reconstrói a lista em um frame que o teste nunca pumpa.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await _pumpFor(tester);

    expect(find.text('Dra. Paula Costa'), findsOneWidget);
    expect(find.text('Dermatologia · CRM 54321/CE'), findsOneWidget);
    expect(find.textContaining('Rua das Palmeiras'), findsOneWidget);
  });
}

/// Bounded pump: the app's recurring timers make pumpAndSettle hang forever
/// under the widget-test fake clock; integration tests use the real binding.
Future<void> _pumpFor(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _resetInMemoryDb() async {
  final db = await DatabaseService.instance.initInMemoryDatabase();
  for (final table in [
    'dose_events',
    'treatments',
    'consultations',
    'doctors',
    'health_plans',
  ]) {
    await db.delete(table);
  }
}


