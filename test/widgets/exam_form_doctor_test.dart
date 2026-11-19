import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:remedios_app_flutter/models/doctor.dart';
import 'package:remedios_app_flutter/models/exam.dart';
import 'package:remedios_app_flutter/providers/doctor_provider.dart';
import 'package:remedios_app_flutter/services/database_service.dart';
import 'package:remedios_app_flutter/widgets/exam_form_dialog.dart';

import '../database_setup.dart';

Exam? _popped;

/// Monta o harness com o provider ANTES do formulário existir — o padrão
/// do repositório: I/O real do sqflite (saveDoctor) roda por await direto
/// no corpo do teste, DEPOIS do pump (não avança dentro de pumpAndSettle).
/// Exame passado ao formulário no próximo [openExamFormWith].
Exam? _existingForNextOpen;

Future<void> pumpHarness(WidgetTester tester, DoctorProvider provider) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<DoctorProvider>.value(
      value: provider,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () async {
                  _popped = await showDialog<Exam>(
                    context: context,
                    builder: (_) =>
                        ExamFormDialog(initialExam: _existingForNextOpen),
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
}

Future<void> openExamForm(WidgetTester tester) async {
  _existingForNextOpen = null;
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

/// Abre o formulário já com um exame existente (edição/registro antigo).
Future<void> openExamFormWith(WidgetTester tester, Exam existing) async {
  _existingForNextOpen = existing;
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

/// Passo 1 (nome do exame) → passo 2 → passo 3 (médico e resultado).
Future<void> goToDoctorStep(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, 'Hemograma completo');
  await tester.tap(find.widgetWithText(FilledButton, 'Continuar'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Continuar'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DoctorProvider doctorProvider;

  setUp(() async {
    _popped = null;
    await setupTestDatabase();
    doctorProvider = DoctorProvider();
    await doctorProvider.initialize();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
  });

  testWidgets(
    'exame exige médico: sem catálogo mostra banner e trava o salvar',
    (tester) async {
      await pumpHarness(tester, doctorProvider);
      await openExamForm(tester);
      await goToDoctorStep(tester);

      // Catálogo vazio: banner com cadastro inline, não beco sem saída.
      expect(
        find.text(
          'Nenhum médico cadastrado. O médico é obrigatório — cadastre aqui '
          'para continuar.',
        ),
        findsOneWidget,
      );
      expect(find.text('Cadastrar médico'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Registrar exame'));
      await tester.pumpAndSettle();

      // Não salvou: o passo continua com o aviso obrigatório.
      expect(
        find.text('Selecione ou cadastre o médico solicitante.'),
        findsOneWidget,
      );
      expect(_popped, isNull);
    },
  );

  testWidgets('exame com médico do catálogo salva vinculado', (tester) async {
    await pumpHarness(tester, doctorProvider);
    // Escrita no SQLite é I/O real: runAsync (padrão do repositório).
    await tester.runAsync(
      () => doctorProvider.saveDoctor(
        const Doctor(id: 'd1', name: 'Dra. Ana', specialty: 'Cardiologia'),
      ),
    );
    await tester.pumpAndSettle();
    await openExamForm(tester);
    await goToDoctorStep(tester);

    await tester.tap(find.text('Selecione'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dra. Ana (Cardiologia)').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Registrar exame'));
    await tester.pumpAndSettle();

    expect(_popped, isNotNull);
    expect(_popped!.doctorId, 'd1');
    // Snapshot: sem texto próprio, o nome vem do médico selecionado.
    expect(_popped!.doctorName, 'Dra. Ana');
  });

  testWidgets('nome do pedido casa com o catálogo e pré-seleciona o médico', (
    tester,
  ) async {
    await pumpHarness(tester, doctorProvider);
    // Escrita no SQLite é I/O real: runAsync (padrão do repositório).
    await tester.runAsync(
      () => doctorProvider.saveDoctor(
        const Doctor(id: 'd1', name: 'Dra. Ana', specialty: 'Cardiologia'),
      ),
    );
    await tester.pumpAndSettle();
    await openExamFormWith(
      tester,
      Exam(
        id: 'e1',
        name: 'Hemograma completo',
        date: DateTime(2026, 1, 10),
        doctorId: '',
        doctorName: 'Dra. Ana',
      ),
    );
    await goToDoctorStep(tester);

    // Registro antigo só com nome: casar com o catálogo evita pedir de novo
    // quem já é conhecido — salvar direto vincula.
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();

    expect(_popped, isNotNull);
    expect(_popped!.doctorId, 'd1');
    expect(_popped!.doctorName, 'Dra. Ana');
  });

  testWidgets('cadastro inline a partir do exame cria e seleciona o médico', (
    tester,
  ) async {
    await pumpHarness(tester, doctorProvider);
    await openExamForm(tester);
    await goToDoctorStep(tester);

    // Banner → cadastro de médico ali mesmo.
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Cadastrar médico'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Cadastrar médico'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nome do médico'),
      'Dr. Bruno',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Continuar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Continuar'));
    await tester.pumpAndSettle();

    // O salvar do médico grava no banco real: o corpo do teste precisa dar
    // espaço ao I/O fora do pumpAndSettle (padrão do repositório).
    await tester.tap(find.widgetWithText(FilledButton, 'Cadastrar'));
    final savedDoctor = await tester.runAsync(() async {
      // Aguarda o I/O real do saveDoctor terminar fora do fake async.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return doctorProvider.doctors.any((doctor) => doctor.name == 'Dr. Bruno');
    });
    expect(savedDoctor, isTrue);

    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Registrar exame'));
    await tester.pumpAndSettle();

    expect(_popped, isNotNull);
    expect(_popped!.doctorId, isNotEmpty);
    expect(_popped!.doctorName, 'Dr. Bruno');
  });
}
