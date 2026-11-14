import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'package:remedios_app_flutter/core/design/record_card.dart';
import 'package:remedios_app_flutter/core/design/stat_card.dart';
import 'package:remedios_app_flutter/models/consultation.dart';
import 'package:remedios_app_flutter/models/doctor.dart';
import 'package:remedios_app_flutter/models/treatment.dart';
import 'package:remedios_app_flutter/providers/consultation_provider.dart';
import 'package:remedios_app_flutter/providers/doctor_provider.dart';
import 'package:remedios_app_flutter/providers/therapy_provider.dart';
import 'package:remedios_app_flutter/providers/user_profile_provider.dart';
import 'package:remedios_app_flutter/screens/consultations_screen.dart';
import 'package:remedios_app_flutter/screens/profile_screen.dart';
import 'package:remedios_app_flutter/screens/treatments_screen.dart';
import 'package:remedios_app_flutter/services/database_service.dart';

import '../database_setup.dart';

/// Migração das telas Tratamentos, Consultas e Perfil para o design system
/// V5: as telas consomem RecordCard/StatCard em vez de decorar Containers.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Inicializações com IO real ficam FORA do corpo de testWidgets: dentro
  // da zona fake do binding o SQLite nunca completa e o teste trava
  // (padrão do widget_test.dart e dos testes de Perfil).
  late TherapyProvider therapy;
  late ConsultationProvider consultations;
  late DoctorProvider doctors;
  late UserProfileProvider profile;

  setUp(() async {
    await initializeDateFormatting('pt_BR');
    await setupTestDatabase();
    therapy = TherapyProvider();
    consultations = ConsultationProvider();
    doctors = DoctorProvider();
    profile = UserProfileProvider();
    await therapy.initialize();
    await consultations.initialize();
    await doctors.initialize();
    await profile.initialize();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
  });

  group('Tratamentos', () {
    testWidgets('resumo em StatCards e cartão do tratamento em RecordCard',
        (tester) async {
      // Escrita no SQLite é IO real: precisa de runAsync dentro do teste.
      await tester.runAsync(
        () => therapy.addTreatment(
          Treatment(
            id: 't1',
            name: 'Losartana',
            dosage: '50mg',
            presentation: 'Comprimido',
            instructions: 'Após o almoço',
            startDate: DateTime(2026, 1, 1),
            endDate: null,
            frequency: TreatmentFrequency.daily,
            doseTimes: const [DoseTime(hour: 8, minute: 0)],
            stock: 30,
            refillThreshold: 10,
          ),
        ),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<TherapyProvider>.value(
          value: therapy,
          child: const MaterialApp(home: Scaffold(body: TreatmentsScreen())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Losartana'), findsOneWidget);

      // Fileira de estatísticas: 1 tratamento ativo, estoque em dia.
      expect(find.byType(StatCard), findsNWidgets(2));
      expect(find.text('tratamento ativo'), findsOneWidget);
      expect(find.text('estoque em dia'), findsOneWidget);

      // O cartão do tratamento é um RecordCard da marca (não um Card M3).
      final recordCards = tester.widgetList<RecordCard>(
        find.byType(RecordCard),
      );
      expect(recordCards, hasLength(1));
      expect(recordCards.first.onTap, isNotNull);
    });
  });

  group('Consultas', () {
    testWidgets('destaque dos próximos 5 dias acende o acento no RecordCard',
        (tester) async {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      // O médico precisa existir antes: consultations tem FK para doctors.
      await tester.runAsync(
        () async {
          await doctors.saveDoctor(
            const Doctor(
              id: 'd1',
              name: 'Dra. Ana Ribeiro',
              specialty: 'Cardiologia',
            ),
          );
          await consultations.saveConsultation(
            Consultation.create(
              doctorId: 'd1',
              date: DateTime(
                tomorrow.year,
                tomorrow.month,
                tomorrow.day,
                10,
                30,
              ),
              title: 'Cardiologia',
            ),
          );
        },
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ConsultationProvider>.value(
              value: consultations,
            ),
            ChangeNotifierProvider<DoctorProvider>.value(value: doctors),
          ],
          child: const MaterialApp(
            home: Scaffold(body: ConsultationsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cardiologia'), findsOneWidget);

      // Estatísticas da tela em StatCards.
      expect(find.byType(StatCard), findsNWidgets(2));
      expect(find.text('próxima consulta'), findsOneWidget);
      expect(find.text('consultas no histórico'), findsOneWidget);

      // A consulta entra na faixa dos próximos 5 dias: o RecordCard
      // correspondente carrega o acento de alerta.
      final highlighted = tester
          .widgetList<RecordCard>(find.byType(RecordCard))
          .where((card) => card.accentColor != null);
      expect(highlighted, isNotEmpty);
    });
  });

  group('Perfil', () {
    testWidgets('cartão de emergência migra para RecordCard com acento vermelho',
        (tester) async {
      // Viewport alto: o formulário tem ~1600px e o cartão fica abaixo
      // da dobra; o ListView lazy não constrói o que está fora da árvore.
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ChangeNotifierProvider<UserProfileProvider>.value(
          value: profile,
          child: const MaterialApp(home: Scaffold(body: ProfileScreen())),
        ),
      );
      await tester.pumpAndSettle();

      // Sem dados de emergência não há cartão.
      expect(find.text('Cartão de emergência'), findsNothing);

      // Uma alergia faz o cartão surgir (mesma interação do teste antigo).
      await tester.enterText(find.byType(TextField).at(3), 'Dipirona');
      await tester.tap(find.byIcon(Icons.add_circle_outline).first);
      await tester.pumpAndSettle();

      expect(find.text('Cartão de emergência'), findsOneWidget);
      expect(find.byTooltip('Compartilhar como imagem'), findsOneWidget);

      // O cartão é um RecordCard da marca com o acento vermelho.
      final emergencyCards = tester
          .widgetList<RecordCard>(find.byType(RecordCard))
          .where((card) => card.accentColor != null);
      expect(emergencyCards, hasLength(1));

      // As seções do Perfil (dados pessoais, contatos, cadastros, backup,
      // privacidade) também vivem em RecordCards.
      expect(find.byType(RecordCard).evaluate().length, greaterThan(3));
    });
  });
}
