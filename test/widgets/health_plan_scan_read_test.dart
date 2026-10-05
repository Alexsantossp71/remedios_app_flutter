import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:remedios_app_flutter/providers/health_plan_provider.dart';
import 'package:remedios_app_flutter/providers/user_profile_provider.dart';
import 'package:remedios_app_flutter/screens/health_plans_screen.dart';
import 'package:remedios_app_flutter/services/card_reader_service.dart';
import 'package:remedios_app_flutter/services/database_service.dart';

import '../database_setup.dart';

/// Regressão do travamento da leitura do cartão.
///
/// O diálogo de "Lendo o cartão…" era exibido com `await showDialog`, mas a
/// única linha que o dispensava vinha depois da chamada de rede. Como
/// `barrierDismissible` é `false` e não há botão de cancelar, o `await`
/// esperava um `pop` que só ocorreria depois da leitura — que só começava
/// depois do `pop`. Deadlock: a imagem nunca era enviada e a tela ficava
/// presa em "carregando" para sempre.
///
/// Os testes anteriores paravam antes da seleção do arquivo, por isso nenhum
/// deles entrou no `_scanCard`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pickerChannel = MethodChannel('plugins.flutter.io/image_picker');

  late HealthPlanProvider planProvider;
  late UserProfileProvider userProvider;
  late Directory tempDir;
  late String imagePath;

  /// Cria um PNG real: o XFile devolvido pelo canal precisa de bytes
  /// em disco para o `readAsBytes` do ImagePicker.
  Future<String> writeFakeCard() async {
    final path = '${tempDir.path}/cartao.png';
    await File(path).writeAsBytes([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    ]);
    return path;
  }

  setUp(() async {
    await setupTestDatabase();
    planProvider = HealthPlanProvider();
    userProvider = UserProfileProvider();
    await planProvider.initialize();
    await userProvider.initialize();
    // Consentimento prévio: o diálogo de autorização tem cobertura própria
    // em health_plan_scan_consent_test.dart e só atrapalharia aqui.
    await userProvider.grantConsent();
    tempDir = await Directory.systemTemp.createTemp('card_scan_test');
    // O arquivo é criado aqui, e não no corpo do teste, porque
    // `setUp` roda fora da zona fake: IO real no corpo de um
    // `testWidgets` nunca completa e travava o runner.
    imagePath = await writeFakeCard();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pickerChannel, null);
    await DatabaseService.instance.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Body que o proxy devolveria para um cartão legível, no mesmo formato que
  /// `api/read-card.ts` usa.
  String readableCardPayload() => jsonEncode({
        'content': jsonEncode({
          'name': 'PLANO SAUDE FAMILIA',
          'provider': 'UNIMED',
          'cardNumber': '1234567890123456',
          'validity': '12/2030',
        }),
      });

  Future<void> pumpScreen(
    WidgetTester tester,
    CardReaderService Function() cardReader,
  ) async {
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
        child: MaterialApp(
          home: HealthPlansScreen(cardReaderFactory: cardReader),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Abre o seletor de origem, escolhe a galeria e deixa a leitura
  /// terminar.
  ///
  /// Fica dentro de `runAsync` porque o ImagePicker e a leitura do
  /// arquivo são IO real. O fluxo atravessa várias etapas
  /// assíncronas (fechar a sheet, o canal do picker, a leitura do
  /// arquivo e a chamada de leitura); cada uma precisa de tempo
  /// real para o IO completar e de um `pump` para drenar a
  /// continuação que ficou na zona fake. Um único `pump` drena
  /// só uma etapa, por isso o loop.
  Future<void> pickFromGallery(WidgetTester tester, String imagePath) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pickerChannel, (call) async {
      if (call.method == 'pickImage') return imagePath;
      return null;
    });
    await tester.runAsync(() async {
      await tester.tap(find.text('Escolher imagem da galeria'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    await tester.pump();
  }

  testWidgets('leitura bem-sucedida envia a imagem e abre a conferência',
      (tester) async {
    final requests = <http.Request>[];

    final service = CardReaderService(
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          readableCardPayload(),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await pumpScreen(tester, () => service);
    await tester.tap(find.text('Adicionar plano'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar imagem do cartão'));
    await tester.pumpAndSettle();

    await pickFromGallery(tester, imagePath);

    // O request realmente saiu. Antes da correção este era o ponto exato do
    // travamento: nada era enviado e o diálogo ficaria aberto para sempre.
    expect(requests, hasLength(1));
    expect(requests.single.url.path, '/api/read-card');
    expect(requests.single.method, 'POST');

    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body['mimeType'], 'image/png');
    expect(
      base64Decode(body['image'] as String),
      isNotEmpty,
      reason: 'os bytes da imagem selecionada vão no corpo da requisição',
    );

    // O diálogo de loading foi dispensado e a conferência abriu.
    expect(find.text('Lendo o cartão…'), findsNothing);
    expect(find.text('Conferir dados do cartão'), findsOneWidget);
  });

  testWidgets('falha de rede fecha o diálogo e oferece o cadastro manual',
      (tester) async {
    final service = CardReaderService(
      client: MockClient((_) async => throw const SocketException('sem rede')),
    );

    await pumpScreen(tester, () => service);
    await tester.tap(find.text('Adicionar plano'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar imagem do cartão'));
    await tester.pumpAndSettle();

    await pickFromGallery(tester, imagePath);

    // Sem isto o usuário ficaria preso em "carregando" sem nunca saber que a
    // leitura falhou — o pior desfecho possível do bug original.
    expect(find.text('Lendo o cartão…'), findsNothing);
    expect(find.text('Conferir dados do cartão'), findsNothing);
    expect(find.textContaining('Sem conexão'), findsOneWidget);
    expect(find.text('Cadastrar manualmente'), findsOneWidget);
  });
}