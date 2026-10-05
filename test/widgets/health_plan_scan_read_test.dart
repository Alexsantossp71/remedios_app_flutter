import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:remedios_app_flutter/providers/health_plan_provider.dart';
import 'package:remedios_app_flutter/providers/user_profile_provider.dart';
import 'package:remedios_app_flutter/screens/health_plans_screen.dart';
import 'package:remedios_app_flutter/services/database_service.dart';

import '../database_setup.dart';

/// Cliente que sempre falha, contando quantas vezes foi acionado.
class _FailingHttpClient extends HttpClient {
  static int attempts = 0;

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    attempts++;
    throw const SocketException('sem rede no teste');
  }

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    attempts++;
    throw const SocketException('sem rede no teste');
  }
}

/// Regressão do travamento da leitura do cartão.
///
/// O diálogo de "Lendo o cartão…" era exibido com `await`, mas a única linha
/// que o dispensava vinha depois da chamada de rede. Como o diálogo não pode
/// ser fechado por toque, o `await` nunca completava, a leitura nunca era
/// enviada e a tela ficava presa em "carregando" para sempre.
///
/// Este teste não depende da rede: o cliente falha de propósito e a断言 é
/// sobre a chamada teriaries e o diálogo ter sido fechado.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HealthPlanProvider planProvider;
  late UserProfileProvider userProvider;
  late Directory tempDir;
  late String imagePath;

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<HealthPlanProvider>.value(value: planProvider),
          ChangeNotifierProvider<UserProfileProvider>.value(value: userProvider),
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
    // Consentimento prévio: o diálogo de autorização tem cobertura própria em
    // health_plan_scan_consent_test.dart e só atrapalharia aqui.
    await userProvider.grantConsent();

    tempDir = await Directory.systemTemp.createTemp('card_scan_test');
    imagePath = '${tempDir.path}/cartao.png';
    // PNG mínimo: o XFile só precisa de bytes reais para readAsBytes.
    await File(imagePath).writeAsBytes(
      Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      ]),
    );

    _FailingHttpClient.attempts = 0;
    const channel = MethodChannel('plugins.flutter.io/image_picker');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'pickImage') return imagePath;
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/image_picker'),
      null,
    );
    await DatabaseService.instance.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets('escolher imagem envia a leitura e fecha o diálogo',
      (tester) async {
    await HttpOverrides.runZoned(
      () async {
        await pumpScreen(tester);

        await tester.tap(find.text('Adicionar plano'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Enviar imagem do cartão'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Escolher imagem da galeria'));
        // O ImagePicker e a leitura do XFile fazem IO real; runAsync deixa
        // esses Futures completarem fora da zona fake do testWidgets.
        await tester.runAsync(() async {
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 400));
        });

        // A leitura precisa ter sido de fato enviada. Antes da correção o
        // fluxo travava no `await showDialog` e esta contagem ficava em 0.
        await tester.pump();
        expect(
          _FailingHttpClient.attempts,
          greaterThan(0),
          reason: 'readCard precisa ser chamado; sem isso a tela trava em '
              '"Lendo o cartão…" para sempre',
        );

        await tester.pumpAndSettle();

        // Diálogo de leitura fechado e erro comunicado com saída manual.
        expect(find.text('Lendo o cartão…'), findsNothing);
        expect(find.textContaining('Sem conexão'), findsOneWidget);
        expect(find.text('Cadastrar manualmente'), findsOneWidget);
      },
      createHttpClient: (_) => _FailingHttpClient(),
    );
  });
}