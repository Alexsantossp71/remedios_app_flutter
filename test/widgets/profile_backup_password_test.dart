import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'package:remedios_app_flutter/providers/user_profile_provider.dart';
import 'package:remedios_app_flutter/screens/profile_screen.dart';
import 'package:remedios_app_flutter/services/database_service.dart';

import '../database_setup.dart';

/// Botão "Criptografar" do diálogo (matcher por predicado — ver
/// profile_autosave_test.dart).
final Finder encryptButton = find.ancestor(
  of: find.text('Criptografar'),
  matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
);

Finder get passwordField => find.widgetWithText(TextFormField, 'Senha do backup');

Finder get confirmField => find.widgetWithText(TextFormField, 'Confirme a senha');

/// Mensagem completa de validação (bug relatado: o texto aparecia cortado
/// com reticências em telas estreitas).
final Finder fullErrorMessage = find.text(
  'A senha precisa ter ao menos 6 caracteres.',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late UserProfileProvider provider;

  Future<void> pumpScreen(
    WidgetTester tester, {
    Size size = const Size(800, 3200),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<UserProfileProvider>.value(
        value: provider,
        child: const MaterialApp(home: Scaffold(body: ProfileScreen())),
      ),
    );
    await tester.pumpAndSettle();

    // A lista é lazy: com viewport baixo o "Exportar" ainda não existe na
    // árvore — rola o ListView até ele existir e depois centraliza-o na
    // tela (scrollUntilVisible pode parar com o botão na borda, o que faz
    // o tap errar o centro).
    await tester.scrollUntilVisible(
      find.text('Exportar'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Exportar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exportar'));
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

  group('diálogo "Proteger backup" (senha mínima de 6 caracteres)', () {
    testWidgets('senha curta mostra a mensagem de alerta POR INTEIRO', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.text('Proteger backup'), findsOneWidget);
      expect(find.text('Use pelo menos 6 caracteres.'), findsOneWidget);

      // 5 caracteres: abaixo do mínimo de 6.
      await tester.enterText(passwordField, 'abc12');
      await tester.tap(encryptButton);
      await tester.pumpAndSettle();

      // O diálogo permanece aberto e o alerta completo está renderizado.
      expect(find.text('Proteger backup'), findsOneWidget);
      expect(fullErrorMessage, findsOneWidget);

      // O Text do erro quebra em até 3 linhas em vez de cortar com
      // reticências (errorMaxLines: 3).
      final errorText = tester.widget<Text>(fullErrorMessage);
      expect(errorText.maxLines, 3);
      expect(errorText.overflow, TextOverflow.ellipsis);
    });

    testWidgets(
      'mensagem completa cabe numa tela estreita de celular (360px) '
      'sem overflow',
      (tester) async {
        await pumpScreen(tester, size: const Size(360, 740));

        await tester.enterText(passwordField, 'abc12');
        await tester.tap(encryptButton);
        await tester.pumpAndSettle();

        // Mensagem inteira presente e nenhum overflow de layout.
        expect(fullErrorMessage, findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('senha de 6 caracteres é aceita e fecha o diálogo', (
      tester,
    ) async {
      await pumpScreen(tester);

      await tester.enterText(passwordField, 'abc123');
      await tester.enterText(confirmField, 'abc123');
      await tester.pump();
      await tester.tap(encryptButton);
      // pump() processa o pop agendado; o pump de 200ms completa a animação
      // de saída e remove a rota da árvore. pumpAndSettle não funciona
      // aqui: a exportação fica pendente na zona fake (I/O SQLite nunca
      // completa sem runAsync — ver profile_autosave_test.dart) e o
      // spinner do cartão animaria para sempre.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Validação passou: diálogo fechou (a exportação segue depois).
      expect(find.text('Proteger backup'), findsNothing);
      expect(fullErrorMessage, findsNothing);
    });

    testWidgets('senhas diferentes falham na confirmação', (tester) async {
      await pumpScreen(tester);

      await tester.enterText(passwordField, 'abc123');
      await tester.enterText(confirmField, 'abc124');
      await tester.tap(encryptButton);
      await tester.pumpAndSettle();

      expect(find.text('Proteger backup'), findsOneWidget);
      expect(find.text('As senhas não coincidem.'), findsOneWidget);
    });
  });
}
