import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'package:remedios_app_flutter/providers/user_profile_provider.dart';
import 'package:remedios_app_flutter/screens/profile_screen.dart';
import 'package:remedios_app_flutter/services/database_service.dart';

import '../database_setup.dart';

/// Botão de salvar do formulário de perfil.
///
/// Não dá para usar `find.widgetWithText(FilledButton, ...)`: `FilledButton.icon`
/// cria um `_FilledButtonWithIcon`, cujo `runtimeType` não é `FilledButton`, e
/// `find.byType` compara por `runtimeType`. O predicado `is ButtonStyleButton`
/// aceita as subclasses.
final Finder saveProfileButton = find.ancestor(
  of: find.text('Salvar perfil'),
  matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late UserProfileProvider provider;

  Future<void> pumpScreen(WidgetTester tester) async {
    // Viewport alto: o formulário do perfil tem ~1600px; sem isso o
    // ListView lazy não constrói o botão "Salvar perfil" e o tap no
    // checkbox cai fora da tela (800x600 padrão).
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

  testWidgets('exibe aviso de privacidade e consentimento destacado',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('Aviso de privacidade'), findsOneWidget);
    // As linhas do aviso são RichText (TextSpan com label em negrito);
    // find.textContaining só enxerga RichText com findRichText: true.
    expect(
      find.textContaining('Finalidade', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('Base legal', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('Controlador', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('art. 18', findRichText: true),
      findsOneWidget,
    );

    expect(find.byType(CheckboxListTile), findsOneWidget);
    expect(find.textContaining('Autorizo o tratamento'), findsOneWidget);

    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox.value, isFalse);
  });

  testWidgets('salvar sem consentimento mostra aviso e não grava',
      (tester) async {
    await pumpScreen(tester);

    await tester.enterText(find.byType(TextFormField).first, 'Maria Silva');
    await tester.ensureVisible(saveProfileButton);
    await tester.tap(saveProfileButton);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Autorize o tratamento dos seus dados de saúde para salvar o perfil.',
      ),
      findsOneWidget,
    );
    expect(provider.profile, isNull);
  });

  testWidgets('com consentimento marcado, salva e registra consentAt',
      (tester) async {
    await pumpScreen(tester);

    await tester.enterText(find.byType(TextFormField).first, 'Maria Silva');

    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);

    await tester.ensureVisible(saveProfileButton);
    await tester.tap(saveProfileButton);
    await tester.pump();
    // O save awaited toca o SQLite (FFI): pumpAndSettle não espera I/O
    // real, então damos tempo de relógio antes de conferir o SnackBar.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Perfil salvo com sucesso!'), findsOneWidget);
    expect(provider.profile, isNotNull);
    expect(provider.profile?.nome, 'Maria Silva');
    expect(provider.profile?.consentAt, isNotNull);

    // Checkbox fica travado (marcado e desabilitado) após registrar.
    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox.value, isTrue);
    expect(checkbox.onChanged, isNull);
    expect(find.textContaining('Consentimento registrado em'), findsOneWidget);
  });
}