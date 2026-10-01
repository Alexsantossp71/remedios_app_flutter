// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:remedios_app_flutter/main.dart';
import 'package:remedios_app_flutter/providers/consultation_provider.dart';
import 'package:remedios_app_flutter/providers/doctor_provider.dart';
import 'package:remedios_app_flutter/providers/therapy_provider.dart';
import 'package:remedios_app_flutter/services/database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DatabaseService.instance.initInMemoryDatabase();
  });

  testWidgets('App loads with title', (tester) async {
    await _pumpApp(tester);

    expect(find.text('Remédio na Hora'), findsOneWidget);
  });

  testWidgets('Doctors catalog is reachable from the main navigation',
      (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.text('Médicos'));
    await tester.pumpAndSettle();

    expect(find.text('Seus médicos'), findsOneWidget);
    expect(find.text('Seu catálogo começa aqui'), findsOneWidget);
  });

  testWidgets('Can add a doctor with contact and location details',
      (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.text('Médicos'));
    await tester.pumpAndSettle();
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
    await tester.tap(find.widgetWithText(DropdownButtonFormField, 'UF do CRM'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RJ').last);
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
    await tester.tap(find.widgetWithText(DropdownButtonFormField, 'UF').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('RJ').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cadastrar').last);
    await tester.pumpAndSettle();

    expect(find.text('Dra. Paula Costa'), findsOneWidget);
    expect(find.text('Dermatologia · CRM 54321/RJ'), findsOneWidget);
    expect(find.textContaining('Rua das Palmeiras'), findsOneWidget);
    expect(find.byTooltip('Verificar gratuitamente no CFM'), findsOneWidget);
  });
}

Future<void> _pumpApp(WidgetTester tester) async {
  final therapyProvider = TherapyProvider();
  final doctorProvider = DoctorProvider();
  final consultationProvider = ConsultationProvider();
  await therapyProvider.initialize();
  await doctorProvider.initialize();
  await consultationProvider.initialize();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: therapyProvider),
        ChangeNotifierProvider.value(value: doctorProvider),
        ChangeNotifierProvider.value(value: consultationProvider),
      ],
      child: const RemediosApp(),
    ),
  );
  await tester.pumpAndSettle();
}
