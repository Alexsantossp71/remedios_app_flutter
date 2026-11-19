import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'package:remedios_app_flutter/core/theme/app_theme.dart';
import 'package:remedios_app_flutter/providers/consultation_provider.dart';
import 'package:remedios_app_flutter/providers/doctor_provider.dart';
import 'package:remedios_app_flutter/providers/exam_provider.dart';
import 'package:remedios_app_flutter/providers/health_plan_provider.dart';
import 'package:remedios_app_flutter/providers/lab_result_provider.dart';
import 'package:remedios_app_flutter/providers/therapy_provider.dart';
import 'package:remedios_app_flutter/providers/user_profile_provider.dart';
import 'package:remedios_app_flutter/screens/main_shell.dart';
import 'package:remedios_app_flutter/services/database_service.dart';

import '../database_setup.dart';

/// Menu central “+”: todas as funcionalidades em um lugar e, para os
/// domínios com leitura de foto, a pergunta manual × foto antes de abrir
/// qualquer formulário.
///
/// Os caminhos de foto precisam do ImagePicker (nativo) e são cobertos até
/// a folha de escolha; o comportamento completo de cada leitura já tem
/// testes próprios (prescription_review, health_plan_scan_read, etc.).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TherapyProvider therapy;
  late DoctorProvider doctors;
  late ConsultationProvider consultations;
  late HealthPlanProvider plans;
  late ExamProvider exams;
  late LabResultProvider labs;
  late UserProfileProvider profile;

  setUp(() async {
    await initializeDateFormatting('pt_BR');
    await setupTestDatabase();
    therapy = TherapyProvider();
    doctors = DoctorProvider();
    consultations = ConsultationProvider();
    plans = HealthPlanProvider();
    exams = ExamProvider();
    labs = LabResultProvider();
    profile = UserProfileProvider();
    await therapy.initialize();
    await doctors.initialize();
    await consultations.initialize();
    await plans.initialize();
    await exams.initialize();
    await labs.initialize();
    await profile.initialize();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
  });

  // Bounded pump: o shell monta a aba Hoje, que agenda timers recorrentes —
  // pumpAndSettle não terminaria nunca sob o relógio falso dos testes.
  Future<void> pump(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TherapyProvider>.value(value: therapy),
          ChangeNotifierProvider<DoctorProvider>.value(value: doctors),
          ChangeNotifierProvider<ConsultationProvider>.value(
            value: consultations,
          ),
          ChangeNotifierProvider<HealthPlanProvider>.value(value: plans),
          ChangeNotifierProvider<ExamProvider>.value(value: exams),
          ChangeNotifierProvider<LabResultProvider>.value(value: labs),
          ChangeNotifierProvider<UserProfileProvider>.value(value: profile),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const MainShell()),
      ),
    );
    await pump(tester);
  }

  Future<void> openCreateMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Cadastrar'));
    await pump(tester);
    await pump(tester);
  }

  testWidgets('menu central lista as seis funcionalidades', (tester) async {
    await pumpShell(tester);
    await openCreateMenu(tester);

    expect(find.text('Medicamento'), findsOneWidget);
    expect(find.text('Consulta'), findsOneWidget);
    expect(find.text('Exame'), findsOneWidget);
    expect(find.text('Laudo'), findsOneWidget);
    expect(find.text('Plano de saúde'), findsOneWidget);
    expect(find.text('Médico'), findsOneWidget);
  });

  testWidgets('Medicamento pergunta manual × foto da receita', (tester) async {
    await pumpShell(tester);
    await openCreateMenu(tester);

    await tester.tap(find.text('Medicamento'));
    await pump(tester);
    await pump(tester);

    // A pergunta vem antes de qualquer formulário.
    expect(find.text('Novo medicamento'), findsOneWidget);
    expect(find.text('Digitar manualmente'), findsOneWidget);
    expect(find.text('Usar foto da receita'), findsOneWidget);
    expect(find.text('Novo tratamento'), findsNothing);

    // Caminho manual abre o formulário de tratamento.
    await tester.tap(find.text('Digitar manualmente'));
    await pump(tester);
    await pump(tester);
    await pump(tester);

    expect(find.text('Novo tratamento'), findsOneWidget);
    expect(find.text('Usar foto da receita'), findsNothing);
  });

  testWidgets('Laudo pergunta manual × foto com IA', (tester) async {
    await pumpShell(tester);
    await openCreateMenu(tester);

    await tester.tap(find.text('Laudo'));
    await pump(tester);
    await pump(tester);

    expect(find.text('Novo laudo'), findsOneWidget);
    expect(find.text('Digitar manualmente'), findsOneWidget);
    expect(find.text('Ler foto com IA'), findsOneWidget);

    await tester.tap(find.text('Digitar manualmente'));
    await pump(tester);
    await pump(tester);
    await pump(tester);

    expect(find.text('Conferir laudo'), findsOneWidget);
  });

  testWidgets('Médico pergunta manual × foto da receita', (tester) async {
    await pumpShell(tester);
    await openCreateMenu(tester);

    await tester.tap(find.text('Médico'));
    await pump(tester);
    await pump(tester);

    expect(find.text('Novo médico'), findsOneWidget);
    expect(find.text('Digitar manualmente'), findsOneWidget);
    expect(find.text('Foto da receita'), findsOneWidget);

    await tester.tap(find.text('Digitar manualmente'));
    await pump(tester);
    await pump(tester);
    await pump(tester);

    expect(find.text('Cadastrar médico'), findsOneWidget);
  });

  testWidgets('Plano de saúde abre a folha própria do módulo', (tester) async {
    await pumpShell(tester);
    await openCreateMenu(tester);

    await tester.tap(find.text('Plano de saúde'));
    await pump(tester);

    expect(find.text('Enviar imagem do cartão'), findsOneWidget);
    expect(find.text('Cadastrar manualmente'), findsOneWidget);
  });

  testWidgets('Exame abre o formulário direto (IA já embutida)', (
    tester,
  ) async {
    await pumpShell(tester);
    await openCreateMenu(tester);

    await tester.tap(find.text('Exame'));
    await pump(tester);
    await pump(tester);

    expect(find.text('Registrar exame'), findsOneWidget);
    expect(find.text('Novo medicamento'), findsNothing);
  });

  testWidgets('Consulta abre o formulário direto', (tester) async {
    await pumpShell(tester);
    await openCreateMenu(tester);

    await tester.tap(find.text('Consulta'));
    await pump(tester);
    await pump(tester);

    expect(find.text('Agendar consulta'), findsOneWidget);
  });
}
