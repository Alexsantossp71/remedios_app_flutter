import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'package:remedios_app_flutter/providers/user_profile_provider.dart';
import 'package:remedios_app_flutter/screens/profile_screen.dart';
import 'package:remedios_app_flutter/services/database_service.dart';

import '../database_setup.dart';

/// Testes do cartão de emergência: condições crônicas ao vivo e o botão
/// de compartilhar como imagem.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late UserProfileProvider provider;

  Future<void> pumpScreen(WidgetTester tester) async {
    // Viewport alto: sem isso o ListView lazy não constrói o cartão e os
    // botões ficam fora da árvore (800x600 padrão).
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<UserProfileProvider>.value(
        value: provider,
        child: const MaterialApp(
          home: Scaffold(body: ProfileScreen()),
        ),
      ),
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

  testWidgets('cartão mostra condições crônicas ao vivo antes de salvar',
      (tester) async {
    await pumpScreen(tester);

    expect(provider.profile, isNull);
    expect(find.text('Cartão de emergência'), findsNothing);

    // Uma alergia faz o cartão surgir (perfil ainda não salvo).
    await tester.enterText(find.byType(TextField).at(3), 'Dipirona');
    await tester.tap(find.byIcon(Icons.add_circle_outline).first);
    await tester.pumpAndSettle();

    expect(find.text('Cartão de emergência'), findsOneWidget);
    // Alergia preenchida; condições crônicas ainda sem valor.
    expect(find.text('Dipirona'), findsNWidgets(2));
    // Editor (label do campo) + linha do cartão = duas ocorrências.
    expect(find.text('Condições crônicas'), findsNWidgets(2));
    expect(find.text('Nenhuma'), findsOneWidget);

    // Condição crônica digitada aparece no cartão no mesmo instante.
    await tester.enterText(find.byType(TextField).at(4), 'Diabetes');
    await tester.tap(find.byIcon(Icons.add_circle_outline).at(1));
    await tester.pumpAndSettle();

    // Chip + cartão = duas ocorrências; "Nenhuma" some do cartão.
    expect(find.text('Diabetes'), findsNWidgets(2));
    expect(find.text('Nenhuma'), findsNothing);
  });

  testWidgets('botão compartilhar existe e trata falha com aviso',
      (tester) async {
    await pumpScreen(tester);

    // Sem dados de emergência não há cartão nem botão.
    expect(find.byTooltip('Compartilhar como imagem'), findsNothing);

    await tester.enterText(find.byType(TextField).at(3), 'Dipirona');
    await tester.tap(find.byIcon(Icons.add_circle_outline).first);
    await tester.pumpAndSettle();

    final shareButton = find.byTooltip('Compartilhar como imagem');
    expect(shareButton, findsOneWidget);

    // Em ambiente de teste não há implementação de compartilhamento
    // (MissingPluginException): o botão deve absorver a falha, avisar o
    // usuário e manter o cartão na tela — nunca derrubar o app.
    await tester.tap(shareButton);
    await tester.pump();
    // A captura (toImage/toByteData) e a chamada de compartilhamento usam
    // async real: dá tempo de relógio antes de conferir o resultado.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Não foi possível compartilhar o cartão agora.'),
      findsOneWidget,
    );
    expect(find.text('Cartão de emergência'), findsOneWidget);
    expect(find.byTooltip('Compartilhar como imagem'), findsOneWidget);
  });
}
