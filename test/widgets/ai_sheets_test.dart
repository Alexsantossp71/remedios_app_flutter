import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:remedios_app_flutter/providers/user_profile_provider.dart';
import 'package:remedios_app_flutter/services/ai_proxy_client.dart';
import 'package:remedios_app_flutter/services/database_service.dart';
import 'package:remedios_app_flutter/widgets/ai_sheet_shell.dart';

import '../database_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AiSheetScaffold — estados', () {
    Widget host(Widget child) => MaterialApp(
          home: Scaffold(body: Center(child: child)),
        );

    testWidgets('mostra carregando e depois o resultado', (tester) async {
      await tester.pumpWidget(
        host(
          AiSheetScaffold<String>(
            title: 'Análise',
            subtitle: 'de teste',
            icon: Icons.auto_awesome_outlined,
            loadingMessage: 'Consultando…',
            load: () async => 'resultado',
            buildResult: (context, result) => Text(result),
          ),
        ),
      );

      // Estado inicial: mensagem de carregamento visível.
      expect(find.text('Consultando…'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.text('resultado'), findsOneWidget);
      // Rodapé obrigatório com o disclaimer educativo.
      expect(find.textContaining('educativa'), findsOneWidget);
    });

    testWidgets('erro exibe mensagem amigável com botão de tentar novamente',
        (tester) async {
      await tester.pumpWidget(
        host(
          AiSheetScaffold<String>(
            title: 'Análise',
            subtitle: 'de teste',
            icon: Icons.auto_awesome_outlined,
            loadingMessage: 'Consultando…',
            load: () async => throw AiException('Limite de solicitações '
                'foi atingido. Aguarde alguns instantes e tente novamente.'),
            buildResult: (context, result) => Text(result),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Limite de solicitações'), findsOneWidget);
      expect(find.text('Tentar novamente'), findsOneWidget);
      expect(find.text('resultado'), findsNothing);
    });

    testWidgets('tentar novamente roda o carregador de novo e renderiza',
        (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        host(
          AiSheetScaffold<String>(
            title: 'Análise',
            subtitle: 'de teste',
            icon: Icons.auto_awesome_outlined,
            loadingMessage: 'Consultando…',
            load: () async {
              attempts++;
              if (attempts == 1) throw AiException('falhou');
              return 'funcionou';
            },
            buildResult: (context, result) => Text(result),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('falhou'), findsOneWidget);

      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.text('funcionou'), findsOneWidget);
    });
  });

  group('ensureAiConsent — fluxo LGPD', () {
    late UserProfileProvider provider;

    setUp(() async {
      await setupTestDatabase();
      provider = UserProfileProvider();
      await provider.initialize();
    });

    tearDown(() async {
      await DatabaseService.instance.close();
    });

    Widget host(Widget child) =>
        ChangeNotifierProvider<UserProfileProvider>.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: child,
              ),
            ),
          ),
        );

    testWidgets('sem consentimento: pergunta e grava ao aceitar',
        (tester) async {
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => ensureAiConsent(context),
              child: const Text('abrir'),
            ),
          ),
        ),
      );
      expect(provider.profile?.aiConsentAt, isNull);

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.text('Autorização para usar a IA'), findsOneWidget);
      // grantAiConsent grava no SQLite (IO real): pumpAndSettle não espera
      // I/O real, então o tap e a espera acontecem em runAsync.
      await tester.runAsync(() async {
        await tester.tap(find.text('Aceito e autorizo'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();

      expect(provider.profile?.aiConsentAt, isNotNull);
    });

    testWidgets('sem consentimento: "Agora não" não grava nada',
        (tester) async {
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => ensureAiConsent(context),
              child: const Text('abrir'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agora não'));
      await tester.pumpAndSettle();

      expect(provider.profile?.aiConsentAt, isNull);
    });

    testWidgets('com consentimento já concedido abre direto, sem diálogo',
        (tester) async {
      // Escrita no SQLite é IO real: runAsync antes de qualquer frame.
      await tester.runAsync(() => provider.grantAiConsent());
      expect(provider.profile?.aiConsentAt, isNotNull);

      var calls = 0;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                calls = (await ensureAiConsent(context)) ? 1 : 0;
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(find.text('Autorização para usar a IA'), findsNothing);
    });
  });
}
