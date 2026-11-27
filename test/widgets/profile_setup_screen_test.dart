import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:remedios_app_flutter/models/user_profile.dart';
import 'package:remedios_app_flutter/screens/profile/profile_setup_screen.dart';

/// Botão por rótulo via predicado ButtonStyleButton.
///
/// Não dá para usar `find.widgetWithText(FilledButton, ...)`: como em
/// profile_consent_test.dart, `FilledButton.icon` cria um
/// `_FilledButtonWithIcon`, cujo `runtimeType` não é `FilledButton`.
Finder buttonWithLabel(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await initializeDateFormatting('pt_BR');
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    required ValueChanged<UserProfile?> onFinish,
  }) async {
    // Viewport alto: o formulário do perfil tem ~1600px; sem isso o
    // ListView lazy não constrói os campos de baixo (peso/altura,
    // consentimento) e o tap cai fora da tela (800x600 padrão).
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: ProfileSetupScreen(onFinish: onFinish)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('mostra o convite com título, formulário e opções de saída', (
    tester,
  ) async {
    final results = <UserProfile?>[];
    await pumpScreen(tester, onFinish: results.add);

    expect(find.text('Quem vai usar o app?'), findsOneWidget);
    expect(find.text('Salvar e começar'), findsOneWidget);
    expect(find.text('Pular por agora'), findsOneWidget);
    // Formulário reutilizado da aba Perfil:
    expect(find.text('Nome'), findsOneWidget);
    expect(find.text('Alergias'), findsOneWidget);
    expect(find.text('Condições crônicas'), findsOneWidget);
    // Consentimento LGPD específico e destacado (art. 11).
    expect(find.textContaining('Autorizo o tratamento'), findsOneWidget);
    // Nada é entregue sem interação do usuário.
    expect(results, isEmpty);
  });

  testWidgets('pular entrega null — nenhum dado é gravado', (tester) async {
    final results = <UserProfile?>[];
    await pumpScreen(tester, onFinish: results.add);

    // Mesmo com dados digitados, pular não entrega perfil.
    await tester.enterText(find.byType(TextFormField).first, 'Maria');
    await tester.tap(find.text('Pular por agora'));
    await tester.pumpAndSettle();

    expect(results, hasLength(1));
    expect(results.single, isNull);
  });

  testWidgets('salvar sem consentimento é bloqueado e não entrega perfil', (
    tester,
  ) async {
    final results = <UserProfile?>[];
    await pumpScreen(tester, onFinish: results.add);

    await tester.enterText(find.byType(TextFormField).first, 'Maria');
    await tester.tap(buttonWithLabel('Salvar e começar'));
    await tester.pumpAndSettle();

    expect(results, isEmpty);
    expect(find.textContaining('Autorize o tratamento'), findsOneWidget);
  });

  testWidgets('validação impede salvar com peso fora da faixa', (tester) async {
    final results = <UserProfile?>[];
    await pumpScreen(tester, onFinish: results.add);

    await tester.enterText(find.byType(TextFormField).first, 'Maria');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Peso (kg)'),
      '9999',
    );
    await tester.tap(find.textContaining('Autorizo o tratamento'));
    await tester.pumpAndSettle();
    await tester.tap(buttonWithLabel('Salvar e começar'));
    await tester.pumpAndSettle();

    expect(results, isEmpty);
    expect(find.text('Peso deve estar entre 1 e 500 kg'), findsOneWidget);
    expect(find.textContaining('Verifique os campos destacados'), findsOneWidget);
  });

  testWidgets('salvar entrega o perfil preenchido com consentimento', (
    tester,
  ) async {
    final results = <UserProfile?>[];
    await pumpScreen(tester, onFinish: results.add);

    await tester.enterText(find.byType(TextFormField).first, 'Maria Silva');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Peso (kg)'),
      '70,5',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Altura (m)'),
      '1,70',
    );
    await tester.tap(find.textContaining('Autorizo o tratamento'));
    await tester.pumpAndSettle();
    await tester.tap(buttonWithLabel('Salvar e começar'));
    await tester.pumpAndSettle();

    expect(results, hasLength(1));
    final profile = results.single!;
    expect(profile.nome, 'Maria Silva');
    // parseNumber aceita vírgula como separador decimal.
    expect(profile.peso, 70.5);
    expect(profile.altura, 1.70);
    expect(profile.consentAt, isNotNull);
    expect(profile.createdAt, isNotEmpty);
  });
}
