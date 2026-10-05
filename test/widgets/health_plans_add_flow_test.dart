import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:remedios_app_flutter/providers/health_plan_provider.dart';
import 'package:remedios_app_flutter/providers/user_profile_provider.dart';
import 'package:remedios_app_flutter/screens/health_plans_screen.dart';
import 'package:remedios_app_flutter/services/database_service.dart';

import '../database_setup.dart';

void main() {
  late HealthPlanProvider provider;

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<HealthPlanProvider>.value(
            value: provider,
          ),
          ChangeNotifierProvider<UserProfileProvider>(
            create: (_) => UserProfileProvider(),
          ),
        ],
        child: const MaterialApp(home: HealthPlansScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() async {
    await setupTestDatabase();
    provider = HealthPlanProvider();
    await provider.initialize();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
  });

  testWidgets('tocar em Adicionar plano abre as duas opções',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Adicionar plano'));
    await tester.pumpAndSettle();

    expect(find.text('Enviar imagem do cartão'), findsOneWidget);
    expect(find.text('Cadastrar manualmente'), findsOneWidget);
  });

  testWidgets('opção manual abre o formulário de plano', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Adicionar plano'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cadastrar manualmente'));
    await tester.pumpAndSettle();

    expect(find.text('Novo Plano de Saúde'), findsOneWidget);
    expect(find.text('Enviar imagem do cartão'), findsNothing);
  });
}