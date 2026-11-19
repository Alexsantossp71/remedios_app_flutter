import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:remedios_app_flutter/models/doctor.dart';
import 'package:remedios_app_flutter/providers/doctor_provider.dart';
import 'package:remedios_app_flutter/services/database_service.dart';
import 'package:remedios_app_flutter/widgets/doctor_inline_creator.dart';

import '../database_setup.dart';

Doctor? _created;

/// Convite de cadastro depois da leitura por foto: a IA identificou um
/// médico fora do catálogo — um toque abre o cadastro pré-preenchido e,
/// ao salvar, o médico criado volta para o formulário selecionar.
Future<void> pumpHarness(WidgetTester tester, DoctorProvider provider) async {
  _created = null;
  await tester.pumpWidget(
    ChangeNotifierProvider<DoctorProvider>.value(
      value: provider,
      child: MaterialApp(
        home: Scaffold(
          body: ScannedDoctorCta(
            scannedName: 'Dra. Helena',
            onDoctorCreated: (doctor) => _created = doctor,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DoctorProvider doctorProvider;

  setUp(() async {
    _created = null;
    await setupTestDatabase();
    doctorProvider = DoctorProvider();
    await doctorProvider.initialize();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
  });

  testWidgets('convite nomeia o médico lido sem criar nada por conta própria', (
    tester,
  ) async {
    await pumpHarness(tester, doctorProvider);

    expect(find.textContaining('Dra. Helena'), findsWidgets);
    expect(find.text('Cadastrar médico'), findsOneWidget);
    // Preencher não é salvar: o catálogo continua vazio até o usuário agir.
    expect(doctorProvider.doctors, isEmpty);
    expect(_created, isNull);
  });

  testWidgets('um toque abre o cadastro preenchido e entrega o médico criado', (
    tester,
  ) async {
    await pumpHarness(tester, doctorProvider);

    await tester.tap(find.widgetWithText(FilledButton, 'Cadastrar médico'));
    await tester.pumpAndSettle();

    // O formulário de médico abre com o nome lido já no campo.
    final nameField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'Nome do médico'),
    );
    expect(nameField.controller!.text, 'Dra. Helena');

    // Salvar de ponta a ponta: passo 1 → 2 → 3 (padrão do formulário).
    await tester.tap(find.widgetWithText(FilledButton, 'Continuar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Continuar'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Cadastrar'));
    // Escrita no SQLite é I/O real: roda fora do fake async (padrão do repo).
    final saved = await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return doctorProvider.doctors.any(
        (doctor) => doctor.name == 'Dra. Helena',
      );
    });
    expect(saved, isTrue);

    await tester.pumpAndSettle();
    expect(_created, isNotNull);
    expect(_created!.name, 'Dra. Helena');
  });
}
