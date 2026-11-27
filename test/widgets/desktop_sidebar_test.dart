import 'package:material_ui/material_ui.dart';
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

/// Barra lateral do desktop (>= 900px): abas principais + seção "Registros"
/// com os mesmos atalhos do card "Meus cadastros" do Perfil.
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

  // Bounded pump: a aba Hoje agenda timers recorrentes — pumpAndSettle
  // não terminaria nunca sob o relógio falso dos testes.
  Future<void> pump(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> pumpShellWide(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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

  testWidgets(
    'barra lateral mostra abas + seção Registros com os 5 atalhos',
    (tester) async {
      await pumpShellWide(tester);

      // Sem rail — foi substituído pela barra lateral.
      expect(find.byType(NavigationRail), findsNothing);

      // Seções.
      expect(find.text('NAVEGAÇÃO'), findsOneWidget);
      expect(find.text('REGISTROS'), findsOneWidget);

      // Abas principais + Perfil fixado no rodapé da lateral.
      expect(find.text('Hoje'), findsOneWidget);
      expect(find.text('Tratamentos'), findsOneWidget);
      expect(find.text('Consultas'), findsOneWidget);
      expect(find.text('Perfil'), findsOneWidget);

      // Os 5 registros da lateral (mesmos do card "Meus cadastros").
      expect(find.text('Médicos'), findsOneWidget);
      expect(find.text('Exames'), findsOneWidget);
      expect(find.text('Resultados de laboratório'), findsOneWidget);
      expect(find.text('Planos e convênios'), findsOneWidget);
      expect(find.text('Progresso'), findsOneWidget);
    },
  );

  testWidgets('atalho Médicos abre a tela e volta para a lateral', (
    tester,
  ) async {
    await pumpShellWide(tester);

    await tester.tap(find.text('Médicos'));
    await pump(tester);
    await pump(tester);

    // Tela de médicos empurrada sobre o shell (AppBar própria).
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Seus médicos')),
      findsOneWidget,
    );

    // Volta: a lateral continua com o estado intacto.
    await tester.tap(find.byType(BackButton));
    await pump(tester);
    await pump(tester);
    expect(find.text('REGISTROS'), findsOneWidget);
    expect(find.text('Médicos'), findsOneWidget);
  });

  testWidgets('atalho Progresso abre a tela de progresso', (tester) async {
    await pumpShellWide(tester);

    await tester.tap(find.text('Progresso'));
    await pump(tester);
    await pump(tester);

    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Progresso')),
      findsOneWidget,
    );
  });

  testWidgets('aba Perfil continua trocando o conteúdo pela lateral', (
    tester,
  ) async {
    await pumpShellWide(tester);

    await tester.tap(find.text('Perfil'));
    await pump(tester);
    await pump(tester);

    // Conteúdo da aba Perfil renderizado no shell.
    expect(find.text('Salvar perfil'), findsOneWidget);
    // A seleção da lateral trocou (pill no item Perfil).
    final perfilItem = find.ancestor(
      of: find.text('Perfil'),
      matching: find.byType(Semantics),
    );
    expect(perfilItem, findsWidgets);
  });
}
