import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:remedios_app_flutter/models/doctor.dart';
import 'package:remedios_app_flutter/providers/user_profile_provider.dart';
import 'package:remedios_app_flutter/services/ai_proxy_client.dart';
import 'package:remedios_app_flutter/services/ai_service.dart';
import 'package:remedios_app_flutter/services/database_service.dart';
import 'package:remedios_app_flutter/widgets/doctor_form_dialog.dart';

import '../database_setup.dart';

/// O cadastro de médico recebe três atalhos de preenchimento e uma
/// restrição: texto colado lido pela IA, rascunho da receita e a consulta
/// CREMESP — e a especialidade só entra pela LISTA FIXA (com o valor
/// legado preservado na edição).

http.Response chat(String content) => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {'content': content},
        'finish_reason': 'stop',
      },
    ],
  }),
  200,
  headers: {'content-type': 'application/json'},
);

Doctor? _popped;

Future<void> pumpHarness(
  WidgetTester tester, {
  required UserProfileProvider userProvider,
  AiService? aiService,
  Doctor? initialDoctor,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<UserProfileProvider>.value(
      value: userProvider,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () async {
                  _popped = await showDialog<Doctor>(
                    context: context,
                    builder: (_) => DoctorFormDialog(
                      initialDoctor: initialDoctor,
                      aiService: aiService,
                    ),
                  );
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

/// A leitura com IA abre um diálogo com animação infinita: os pumps com
/// tempo real (padrão do repositório) drenam a chamada e dispensam o
/// diálogo antes de qualquer pumpAndSettle.
Future<void> pasteAndFill(WidgetTester tester, String text) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Colar ou digitar os dados do médico'),
    text,
  );
  await tester.pump();
  await tester.runAsync(() async {
    await tester.tap(find.text('Preencher com IA'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late UserProfileProvider userProvider;

  setUp(() async {
    _popped = null;
    await setupTestDatabase();
    userProvider = UserProfileProvider();
    await userProvider.initialize();
    // Consentimento prévio: o diálogo de autorização tem cobertura própria
    // em health_plan_scan_consent_test.dart e só atrapalharia aqui.
    await userProvider.grantAiConsent();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
  });

  AiService aiWith(String content) => AiService(
    proxyClient: AiProxyClient(
      client: MockClient((_) async => chat(content)),
      isWebOverride: false,
    ),
  );

  testWidgets(
    'IA preenche nome, especialidade, telefone e avisa para conferir',
    (tester) async {
      final ai = aiWith(
        jsonEncode({
          'nome': 'Dra. Ana Silva',
          'especialidade': 'Cardiologia',
          'crm': '123456',
          'uf': 'SP',
          'telefone': '(11) 98888-7777',
        }),
      );
      await pumpHarness(tester, userProvider: userProvider, aiService: ai);

      await pasteAndFill(
        tester,
        'Minha médica: Dra. Ana Silva, CRM 123456-SP, cardiologista, '
        '(11) 98888-7777',
      );

      // Nome no campo (sem Dr./Dra.), especialidade na lista fixa, telefone.
      expect(find.text('Ana Silva'), findsWidgets);
      expect(find.text('Cardiologia'), findsWidgets);
      expect(find.text('(11) 98888-7777'), findsOneWidget);
      // O aviso de confiança por conferência fica no cabeçalho da sheet.
      expect(
        find.text('Preenchido pela IA — confira antes de salvar.'),
        findsOneWidget,
      );
      expect(
        find.text('Dados aplicados. Confira antes de salvar.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('CRM e UF lidos pela IA ficam no passo 2', (tester) async {
    final ai = aiWith(
      jsonEncode({
        'nome': 'João Pereira',
        'especialidade': '',
        'crm': '123456',
        'uf': 'SP',
        'telefone': '',
      }),
    );
    await pumpHarness(tester, userProvider: userProvider, aiService: ai);

    await pasteAndFill(tester, 'Dr. João Pereira CRM 123456-SP');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    // Passo 2: CRM numérico e UF do dropdown já selecionada. O hint do
    // campo CRM é exatamente "123456", então o valor é conferido no
    // EditableText (o hint fica na árvore mesmo preenchido).
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is EditableText && widget.controller.text == '123456',
      ),
      findsOneWidget,
    );
    expect(find.text('SP'), findsWidgets);
  });

  testWidgets('texto que não é um médico mostra a mensagem da IA', (
    tester,
  ) async {
    final ai = aiWith(jsonEncode({'error': 'not_a_doctor'}));
    await pumpHarness(tester, userProvider: userProvider, aiService: ai);

    await pasteAndFill(tester, 'compre leite e pão no mercado');

    expect(
      find.textContaining('não parece conter dados de um médico'),
      findsOneWidget,
    );
    // Nada foi preenchido: o nome continua vazio.
    expect(find.text('Ana Silva'), findsNothing);
  });

  testWidgets('colar vazio pede texto e não chama a IA', (tester) async {
    final ai = aiWith(jsonEncode({'nome': 'Ninguém'}));
    await pumpHarness(tester, userProvider: userProvider, aiService: ai);

    await tester.tap(find.text('Preencher com IA'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Cole ou digite os dados'), findsOneWidget);
    expect(find.text('Ninguém'), findsNothing);
  });

  testWidgets('especialidade é lista fixa e o valor legado é preservado', (
    tester,
  ) async {
    await pumpHarness(
      tester,
      userProvider: userProvider,
      initialDoctor: const Doctor(
        id: 'd1',
        name: 'Dr. Old',
        specialty: 'Dentista',
      ),
    );

    // Valor legado (fora da lista) aparece selecionado ao editar.
    expect(find.text('Dentista'), findsOneWidget);

    // A lista fixa abre com as especialidades médicas do CFM. O dropdown
    // pode ficar abaixo da dobra (widgets fora do viewport não são
    // construídos): ensureVisible antes do tap e dragUntilVisible no menu
    // (mesma técnica do teste de UF do CRM).
    await tester.ensureVisible(find.byKey(const ValueKey('doctorSpecialty')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('doctorSpecialty')));
    await tester.pumpAndSettle();
    // O menu abre rolando até o valor selecionado ('Dentista', meio da
    // lista) e os itens são lazy: arrasta até 'Cardiologia' existir. Se o
    // menu já abriu no topo, o loop nem roda.
    for (var i = 0; i < 8 && find.text('Cardiologia').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).last, const Offset(0, 300));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Cardiologia').last);
    await tester.pumpAndSettle();

    // Valor selecionado: o campo pode ter ficado fora da tela de novo.
    await tester.ensureVisible(find.byKey(const ValueKey('doctorSpecialty')));
    await tester.pumpAndSettle();
    expect(find.text('Cardiologia'), findsOneWidget);
    expect(find.text('Dentista'), findsNothing);

    // Salvar de ponta a ponta: passo 1 → 2 → 3.
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(_popped, isNotNull);
    expect(_popped!.specialty, 'Cardiologia');
    expect(_popped!.name, 'Dr. Old');
  });

  testWidgets('passo 2 traz o link de conferência manual no portal do CFM', (
    tester,
  ) async {
    await pumpHarness(tester, userProvider: userProvider);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nome do médico'),
      'Dra. Teste',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(find.text('Conferir no portal do CFM'), findsOneWidget);
    expect(
      find.textContaining('A busca automática pelo CRM cobre o conselho de SP'),
      findsOneWidget,
    );
  });
}
