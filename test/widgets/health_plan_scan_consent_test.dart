import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:remedios_app_flutter/providers/health_plan_provider.dart';
import 'package:remedios_app_flutter/providers/user_profile_provider.dart';
import 'package:remedios_app_flutter/screens/health_plans_screen.dart';
import 'package:remedios_app_flutter/services/database_service.dart';

import '../database_setup.dart';

void main() {
  late HealthPlanProvider planProvider;
  late UserProfileProvider userProvider;

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<HealthPlanProvider>.value(
            value: planProvider,
          ),
          ChangeNotifierProvider<UserProfileProvider>.value(
            value: userProvider,
          ),
        ],
        child: const MaterialApp(home: HealthPlansScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() async {
    await setupTestDatabase();
    planProvider = HealthPlanProvider();
    userProvider = UserProfileProvider();
    await planProvider.initialize();
    await userProvider.initialize();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
  });

  testWidgets(
      'sem consentimento, enviar imagem exige autorização antes do seletor',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Adicionar plano'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar imagem do cartão'));
    await tester.pumpAndSettle();

    // O diálogo de consentimento aparece ANTES do seletor de origem.
    expect(find.text('Autorização necessária'), findsOneWidget);
    expect(find.text('Tirar foto do cartão'), findsNothing);
  });

  testWidgets('cancelar o consentimento volta sem abrir o seletor',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Adicionar plano'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar imagem do cartão'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(find.text('Autorização necessária'), findsNothing);
    expect(find.text('Tirar foto do cartão'), findsNothing);
    // Consentimento segue ausente.
    expect(userProvider.profile?.consentAt, isNull);
  });

  testWidgets('aceitar registra o consentimento e abre o seletor',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Adicionar plano'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar imagem do cartão'));
    await tester.pumpAndSettle();
    // grantConsent grava no SQLite (IO real); runAsync deixa os Futures
    // reais completarem fora da zona fake do testWidgets.
    await tester.runAsync(() async {
      await tester.tap(find.text('Aceito e autorizo'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    expect(find.text('Tirar foto do cartão'), findsOneWidget);
    expect(userProvider.profile?.consentAt, isNotNull);
  });

  group('com consentimento prévio', () {
    setUp(() async {
      await userProvider.grantConsent();
    });

    testWidgets('com consentimento já registrado, o diálogo não volta',
        (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('Adicionar plano'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enviar imagem do cartão'));
      await tester.pumpAndSettle();

      expect(find.text('Autorização necessária'), findsNothing);
      expect(find.text('Tirar foto do cartão'), findsOneWidget);
    });
  });
}
