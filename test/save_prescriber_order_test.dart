import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:remedios_app_flutter/models/treatment.dart';
import 'package:remedios_app_flutter/providers/doctor_provider.dart';
import 'package:remedios_app_flutter/providers/therapy_provider.dart';
import 'package:remedios_app_flutter/screens/create_flows.dart';
import 'package:remedios_app_flutter/services/database_service.dart';

import 'database_setup.dart';

/// Regressão do bug de produção: `saveTreatmentWithPrescriber` gravava o
/// registro de receita **antes** do tratamento — e `treatment_prescriptions`
/// tem foreign key para `treatments` com `PRAGMA foreign_keys = ON`, então
/// cadastro novo violava a constraint (sqlite 787) e o tratamento era
/// perdido no web. A ordem correta é: tratamento primeiro, registro depois.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TherapyProvider therapy;
  late DoctorProvider doctors;

  setUp(() async {
    await initializeDateFormatting('pt_BR');
    await setupTestDatabase();
    therapy = TherapyProvider();
    doctors = DoctorProvider();
    await therapy.initialize();
    await doctors.initialize();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
  });

  /// Monta os providers e devolve um BuildContext dentro deles — a chamada
  /// de `saveTreatmentWithPrescriber` é await direto no corpo do teste
  /// (I/O real do sqflite não avança dentro de pumpAndSettle).
  Future<BuildContext> pumpHost(WidgetTester tester) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TherapyProvider>.value(value: therapy),
          ChangeNotifierProvider<DoctorProvider>.value(value: doctors),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                captured = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return captured;
  }

  Treatment losartanaWithPrescriber({
    String id = 'tx-losartana-1',
    String doctorName = 'Dr. Regressão',
  }) => Treatment(
    id: id,
    name: 'LOSARTANA POTASSICA',
    dosage: '50 mg',
    presentation: 'COM REV CT BL AL OPC X 30',
    instructions: '',
    startDate: DateTime(2026, 11, 15),
    endDate: null,
    frequency: TreatmentFrequency.daily,
    doseTimes: const [DoseTime(hour: 8, minute: 0)],
    stock: null,
    refillThreshold: null,
    prescriberName: doctorName,
    prescribedOn: DateTime(2026, 11, 10),
  );

  testWidgets(
    'cadastro novo com prescritor grava tratamento e registro de receita',
    (tester) async {
      final treatment = losartanaWithPrescriber();
      final context = await pumpHost(tester);

      // Escrita no SQLite é I/O real: runAsync (padrão do brand_screens_test).
      await tester.runAsync(
        () => saveTreatmentWithPrescriber(context, treatment),
      );
      await tester.pumpAndSettle();

      // Tratamento persistido (antes da correção, a FK derrubava o cadastro
      // inteiro — o tratamento não aparecia e nem o registro nascia).
      expect(
        therapy.treatments.where((t) => t.id == treatment.id),
        hasLength(1),
      );

      // Registro "quem receitou e em que dia" no histórico, vinculado ao
      // médico criado no catálogo.
      final records = therapy.prescriptionRecordsFor(treatment.id);
      expect(records, hasLength(1));
      expect(records.first.doctorName, 'Dr. Regressão');
      expect(records.first.treatmentId, treatment.id);
      expect(doctors.doctors.map((d) => d.name), contains('Dr. Regressão'));
    },
  );

  testWidgets('edição sem mudar a receita não multiplica registros', (
    tester,
  ) async {
    final treatment = losartanaWithPrescriber();
    final context = await pumpHost(tester);

    await tester.runAsync(
      () => saveTreatmentWithPrescriber(context, treatment),
    );
    await tester.pumpAndSettle();
    expect(therapy.prescriptionRecordsFor(treatment.id), hasLength(1));

    // Mesma receita: quem receitou e o dia não mudaram — só as instruções.
    final untouched = treatment.copyWith(instructions: 'após o almoço');
    await tester.runAsync(
      () =>
          saveTreatmentWithPrescriber(context, untouched, previous: treatment),
    );
    await tester.pumpAndSettle();

    expect(therapy.prescriptionRecordsFor(treatment.id), hasLength(1));
    expect(
      therapy.treatments.firstWhere((t) => t.id == treatment.id).instructions,
      'após o almoço',
    );
  });

  testWidgets('renovação de receita na edição cria registro novo', (
    tester,
  ) async {
    final treatment = losartanaWithPrescriber();
    final context = await pumpHost(tester);

    await tester.runAsync(
      () => saveTreatmentWithPrescriber(context, treatment),
    );
    await tester.pumpAndSettle();

    final renewed = treatment.copyWith(
      prescriberName: 'Dra. Renovada',
      prescribedOn: DateTime(2026, 11, 15),
    );
    await tester.runAsync(
      () => saveTreatmentWithPrescriber(context, renewed, previous: treatment),
    );
    await tester.pumpAndSettle();

    final records = therapy.prescriptionRecordsFor(treatment.id);
    expect(records, hasLength(2));
    // Mais recente primeiro — a receita atual vem antes da antiga.
    expect(records.first.doctorName, 'Dra. Renovada');
    expect(records.last.doctorName, 'Dr. Regressão');
  });

  testWidgets('cadastro sem prescritor não cria registro', (tester) async {
    final treatment = Treatment(
      id: 'tx-sem-prescritor',
      name: 'LOSARTANA POTASSICA',
      dosage: '50 mg',
      presentation: 'COM REV CT BL AL OPC X 30',
      instructions: '',
      startDate: DateTime(2026, 11, 15),
      endDate: null,
      frequency: TreatmentFrequency.daily,
      doseTimes: const [DoseTime(hour: 8, minute: 0)],
      stock: null,
      refillThreshold: null,
    );
    final context = await pumpHost(tester);

    await tester.runAsync(
      () => saveTreatmentWithPrescriber(context, treatment),
    );
    await tester.pumpAndSettle();

    expect(therapy.treatments, hasLength(1));
    expect(therapy.prescriptionRecordsFor(treatment.id), isEmpty);
    expect(doctors.doctors, isEmpty);
  });
}
