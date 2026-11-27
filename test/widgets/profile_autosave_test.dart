import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'package:remedios_app_flutter/models/user_profile.dart';
import 'package:remedios_app_flutter/providers/user_profile_provider.dart';
import 'package:remedios_app_flutter/screens/profile_screen.dart';
import 'package:remedios_app_flutter/screens/profile/profile_setup_screen.dart';
import 'package:remedios_app_flutter/services/database_service.dart';

import '../database_setup.dart';

/// Botão "Salvar perfil" (FilledButton.icon cria uma subclasse, então o
/// matcher é por predicado — ver profile_consent_test.dart).
final Finder saveProfileButton = find.ancestor(
  of: find.text('Salvar perfil'),
  matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
);

/// Campos TextField do formulário, na ordem visual: 0 Nome, 1 CPF,
/// 2 Telefone, 3 editor de Alergias, 4 editor de Condições, 5 Peso,
/// 6 Altura, 7 Observações (os TextFormField contêm um TextField interno).
Finder allergyField = find.byType(TextField).at(3);
Finder conditionsField = find.byType(TextField).at(4);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late UserProfileProvider provider;

  Future<void> pumpScreen(WidgetTester tester) async {
    // Viewport alto: o formulário tem ~2000px com os contatos dentro; sem
    // isso o ListView lazy não constrói os editores abaixo da dobra.
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<UserProfileProvider>.value(
        value: provider,
        child: const MaterialApp(home: Scaffold(body: ProfileScreen())),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Cria um perfil JÁ SALVO (opcionalmente com alergias) e, por padrão,
  /// com consentimento registrado — pré-condição do auto-save.
  ///
  /// O I/O real do SQLite (FFI) precisa de `runAsync`: dentro da zona
  /// fake-async do testWidgets o future nunca completa.
  Future<void> seedProfile(
    WidgetTester tester, {
    List<String> alergias = const [],
    bool withConsent = true,
  }) async {
    final now = DateTime.now().toUtc();
    await tester.runAsync(() async {
      await provider.saveProfile(
        UserProfile(
          nome: 'Maria Auto',
          alergias: alergias,
          consentAt: withConsent ? now : null,
          createdAt: now.toIso8601String(),
          updatedAt: now.toIso8601String(),
        ),
      );
    });
  }

  /// Dispara o debounce do auto-save (700 ms, relógio fake do teste) e dá
  /// tempo real para o I/O do SQLite completar — mesma técnica do
  /// profile_consent_test.
  Future<void> settleAutosave(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 800));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();
  }

  setUp(() async {
    await initializeDateFormatting('pt_BR');
    await setupTestDatabase();
    provider = UserProfileProvider();
    await provider.initialize();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
  });

  group('auto-save do bloco de emergência', () {
    testWidgets(
      'alergia adicionada persiste sem tocar em "Salvar perfil" '
      '(bug relatado: cartão mostrava ao vivo, dado sumia ao voltar)',
      (tester) async {
        await seedProfile(tester);
        await pumpScreen(tester);

        // Adiciona uma alergia pelo editor (chip), SEM salvar pelo botão.
        await tester.enterText(allergyField, 'Dipirona');
        await tester.tap(find.byIcon(Icons.add_circle_outline).first);
        await settleAutosave(tester);

        // O provider gravou sozinho — o cartão mostra o que está no banco.
        expect(provider.profile?.alergias, ['Dipirona']);

        // Nova instância (= recarregar o app): a alergia volta. O I/O do
        // SQLite dentro de testWidgets precisa de runAsync (zona fake).
        final reloaded = UserProfileProvider();
        await tester.runAsync(reloaded.initialize);
        expect(reloaded.profile?.alergias, ['Dipirona']);
        expect(reloaded.profile?.nome, 'Maria Auto');
        expect(reloaded.profile?.consentAt, isNotNull);
      },
    );

    testWidgets('condição crônica adicionada persiste por auto-save', (
      tester,
    ) async {
      await seedProfile(tester);
      await pumpScreen(tester);

      await tester.enterText(conditionsField, 'Hipertensão');
      await tester.tap(find.byIcon(Icons.add_circle_outline).at(1));
      await settleAutosave(tester);

      expect(provider.profile?.condicoesCronicas, ['Hipertensão']);

      final reloaded = UserProfileProvider();
      await tester.runAsync(reloaded.initialize);
      expect(reloaded.profile?.condicoesCronicas, ['Hipertensão']);
    });

    testWidgets('remover todos os chips persiste a lista vazia', (
      tester,
    ) async {
      await seedProfile(tester, alergias: const ['Dipirona', 'Látex']);
      await pumpScreen(tester);

      // Dois chips renderizados no editor.
      expect(find.text('Dipirona'), findsWidgets);
      expect(find.text('Látex'), findsWidgets);

      // Remove os dois pelo "x" dos chips (InputChip delete).
      await tester.tap(find.byIcon(Icons.close).first);
      await settleAutosave(tester);
      await tester.tap(find.byIcon(Icons.close).first);
      await settleAutosave(tester);

      expect(provider.profile?.alergias, isEmpty);
      final reloaded = UserProfileProvider();
      await tester.runAsync(reloaded.initialize);
      expect(reloaded.profile?.alergias, isEmpty);
    });

    testWidgets('sem perfil salvo o auto-save não grava (LGPD)', (
      tester,
    ) async {
      await pumpScreen(tester);

      await tester.enterText(allergyField, 'Dipirona');
      await tester.tap(find.byIcon(Icons.add_circle_outline).first);
      await settleAutosave(tester);

      expect(provider.profile, isNull);
      // O chip continua no formulário e o cartão de emergência surge ao
      // vivo (alergias não vazias) — duas ocorrências do texto.
      expect(find.text('Dipirona'), findsNWidgets(2));
    });

    testWidgets(
      'perfil salvo SEM consentAt não é alterado pelo auto-save (art. 11)',
      (tester) async {
        await seedProfile(tester, withConsent: false);
        await pumpScreen(tester);

        await tester.enterText(allergyField, 'Dipirona');
        await tester.tap(find.byIcon(Icons.add_circle_outline).first);
        await settleAutosave(tester);

        // O auto-save não alterou a linha salva: consentAt segue null e a
        // alergia não foi gravada — consentimento vem antes do tratamento.
        expect(provider.profile?.consentAt, isNull);
        expect(provider.profile?.alergias, isEmpty);
      },
    );

    testWidgets('botão "Salvar perfil" continua gravando o formulário', (
      tester,
    ) async {
      await seedProfile(tester);
      await pumpScreen(tester);

      await tester.enterText(find.byType(TextFormField).first, 'Maria Silva');
      await tester.ensureVisible(saveProfileButton);
      await tester.tap(saveProfileButton);
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Perfil salvo com sucesso!'), findsOneWidget);
      expect(provider.profile?.nome, 'Maria Silva');
    });
  });

  group('layout: contatos de emergência logo depois de Observações', () {
    testWidgets('seção aparece uma única vez, entre Observações e o aviso', (
      tester,
    ) async {
      await pumpScreen(tester);

      final titleFinder = find.text('Contatos de emergência');
      expect(titleFinder, findsOneWidget);

      // Ordem vertical: Observações < Contatos < Aviso de privacidade.
      final observacoesTop = tester
          .getTopLeft(find.widgetWithText(TextFormField, 'Observações'))
          .dy;
      final contatosTop = tester.getTopLeft(titleFinder).dy;
      final avisoTop = tester.getTopLeft(find.text('Aviso de privacidade')).dy;
      expect(contatosTop, greaterThan(observacoesTop));
      expect(avisoTop, greaterThan(contatosTop));
    });

    testWidgets('convite de primeiro uso NÃO mostra contatos de emergência', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(home: ProfileSetupScreen(onFinish: (_) {})),
      );
      await tester.pumpAndSettle();

      expect(find.text('Quem vai usar o app?'), findsOneWidget);
      expect(find.text('Contatos de emergência'), findsNothing);
    });
  });
}
