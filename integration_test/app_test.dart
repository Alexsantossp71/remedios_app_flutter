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

  group('App Initialization Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await _resetInMemoryDb();
    });

    testWidgets('App loads with title and main navigation', (tester) async {
      await _pumpApp(tester);

      await _waitForText(tester, 'Remédio na Hora');
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('Navigate to Médicos tab', (tester) async {
      await _pumpApp(tester);

      await _waitForText(tester, 'Médicos');
      await tester.tap(find.text('Médicos'));
      await tester.pumpAndSettle();
      await _waitForText(tester, 'Seus médicos');

      expect(find.text('Seu catálogo começa aqui'), findsOneWidget);
    });

    testWidgets('Navigate to Tratamentos tab', (tester) async {
      await _pumpApp(tester);

      await _waitForText(tester, 'Tratamentos');
      await tester.tap(find.text('Tratamentos'));
      await tester.pumpAndSettle();
      await _waitForText(tester, 'Comece seu tratamento');
    });

    testWidgets('Navigate to Hoje tab', (tester) async {
      await _pumpApp(tester);

      await _waitForText(tester, 'Hoje');
      await tester.tap(find.text('Hoje'));
      await tester.pumpAndSettle();

      expect(find.text('Hoje'), findsOneWidget);
    });

    testWidgets('Navigate to Consultas tab', (tester) async {
      await _pumpApp(tester);

      await _waitForText(tester, 'Consultas');
      await tester.tap(find.text('Consultas'));
      await tester.pumpAndSettle();

      await _waitForText(tester, 'Nenhuma consulta agendada');
    });

    testWidgets('Navigate to Progresso tab', (tester) async {
      await _pumpApp(tester);

      await _waitForText(tester, 'Progresso');
      await tester.tap(find.text('Progresso'));
      await tester.pumpAndSettle();

      await _waitForText(tester, 'Histórico de doses');
    });

    testWidgets('Navigate to Perfil tab', (tester) async {
      await _pumpApp(tester);

      await _waitForText(tester, 'Perfil');
      await tester.tap(find.text('Perfil'));
      await tester.pumpAndSettle();

      await _waitForText(tester, 'Preferências');
    });
  });

  group('Doctor Management Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await _resetInMemoryDb();
    });

    testWidgets('Can add a doctor with contact and location details',
        (tester) async {
      // The dialog layout overflows the default 800x600 test surface.
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await _pumpApp(tester);

      await _waitForText(tester, 'Médicos');
      await tester.tap(find.text('Médicos'));
      await tester.pumpAndSettle();

      await _waitForText(tester, 'Cadastrar primeiro médico');
      await tester.tap(find.text('Cadastrar primeiro médico'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome do médico'),
        'Dra. Paula Costa',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Especialidade'),
        'Dermatologia',
      );
      await tester.enterText(find.widgetWithText(TextFormField, 'CRM'), '54321');

      // DropdownButtonFormField<String> — use keys (generic type differs).
      await tester.ensureVisible(find.byKey(const ValueKey('crmStateUf')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('crmStateUf')));
      await tester.pumpAndSettle();
      await _waitForText(tester, 'CE');
      await tester.tap(find.text('CE').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Telefone'),
        '(21) 99999-0000',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Clínica ou consultório'),
        'Clínica Central',
      );
      await tester.tap(find.text('Preencher endereço sem CEP'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Rua ou avenida'),
        'Rua das Palmeiras',
      );
      await tester.enterText(find.widgetWithText(TextFormField, 'Número'), '45');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Cidade'), 'Niterói');

      await tester.ensureVisible(find.byKey(const ValueKey('addressUf')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('addressUf')));
      await tester.pumpAndSettle();
      await _waitForText(tester, 'CE');
      await tester.tap(find.text('CE').last);
      await tester.pumpAndSettle();

      await _waitForText(tester, 'Cadastrar');
      await tester.tap(find.text('Cadastrar').last);
      await tester.pumpAndSettle();

      await _waitForText(tester, 'Dra. Paula Costa');
      expect(find.text('Dermatologia · CRM 54321/CE'), findsOneWidget);
      expect(find.textContaining('Rua das Palmeiras'), findsOneWidget);
    });
  });
}

/// Polls for a widget with the given text, pumping between attempts.
/// Providers load asynchronously after pumpAndSettle, so plain expectations
/// are flaky; this waits until the content is visible.
Future<void> _waitForText(
  WidgetTester tester,
  String text, {
  int maxAttempts = 50,
}) async {
  for (var i = 0; i < maxAttempts; i++) {
    if (find.text(text).evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  final visible = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data)
      .toList();
  debugPrint('VISIBLE TEXTS AT TIMEOUT: $visible');
  fail('Timeout waiting for text: "$text"');
}

/// Reuses (or creates) the in-memory test database and wipes all tables so
/// each test starts from a clean state.
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

