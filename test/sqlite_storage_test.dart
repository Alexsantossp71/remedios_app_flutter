import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:remedios_app_flutter/models/consultation.dart';
import 'package:remedios_app_flutter/models/doctor.dart';
import 'package:remedios_app_flutter/models/dose_event.dart';
import 'package:remedios_app_flutter/models/prescription_record.dart';
import 'package:remedios_app_flutter/models/treatment.dart';
import 'package:remedios_app_flutter/services/consultation_storage_service.dart';
import 'package:remedios_app_flutter/services/database_service.dart';
import 'package:remedios_app_flutter/services/doctor_storage_service.dart';
import 'package:remedios_app_flutter/services/therapy_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DatabaseService dbService;
  late TherapyStorageService therapyService;
  late DoctorStorageService doctorService;
  late ConsultationStorageService consultationService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dbService = DatabaseService.instance;
    await dbService.initInMemoryDatabase();

    therapyService = TherapyStorageService(dbService: dbService);
    doctorService = DoctorStorageService(dbService: dbService);
    consultationService = ConsultationStorageService(dbService: dbService);
  });

  group('SQLite Storage and UTC integrity', () {
    test('TherapyStorageService saves and loads treatments and doses correctly', () async {
      final now = DateTime.now();
      final treatment = Treatment(
        id: 'treat-1',
        name: 'Amoxicilina',
        dosage: '500mg',
        presentation: 'Cápsula',
        instructions: 'Tomar após as refeições',
        startDate: DateTime(now.year, now.month, now.day, 8, 0),
        endDate: DateTime(now.year, now.month, now.day + 7, 8, 0),
        frequency: TreatmentFrequency.daily,
        doseTimes: const [DoseTime(hour: 8, minute: 0), DoseTime(hour: 20, minute: 0)],
        stock: 14,
        refillThreshold: 4,
        isArchived: false,
      );

      await therapyService.saveTreatment(treatment);
      final loadedTreatments = await therapyService.loadTreatments();
      expect(loadedTreatments.length, 1);
      final loaded = loadedTreatments.first;
      expect(loaded.id, 'treat-1');
      expect(loaded.name, 'Amoxicilina');
      expect(loaded.doseTimes.length, 2);
      expect(loaded.doseTimes.first.hour, 8);
      expect(loaded.doseTimes.last.hour, 20);
      expect(loaded.stock, 14);

      final dose = DoseEvent(
        id: 'dose-1',
        treatmentId: 'treat-1',
        scheduledAt: DateTime.utc(2026, 9, 29, 12, 0),
        status: DoseStatus.taken,
        completedAt: DateTime.utc(2026, 9, 29, 12, 5),
      );

      await therapyService.saveDoseEvent(dose);
      final loadedDoses = await therapyService.loadDoseEvents();
      expect(loadedDoses.length, 1);
      expect(loadedDoses.first.id, 'dose-1');
      expect(loadedDoses.first.status, DoseStatus.taken);
    });

    test('Treatment semanal persiste e recarrega com os dias da semana', () async {
      // Datas FIXAS: o teste é sobre a regra de agendamento semanal, não
      // sobre "hoje". Usar o dia corrente como início fez este teste quebrar
      // sozinho quando o calendário passou do sábado fixo nas expectativas.
      final treatment = Treatment(
        id: 'treat-weekly',
        name: 'Metotrexato',
        dosage: '15MG',
        presentation: 'Comprimido',
        instructions: 'Tomar 1 comprimido por semana, aos sábados',
        startDate: DateTime(2026, 11, 1, 8, 0),
        endDate: null,
        frequency: TreatmentFrequency.weekly,
        doseTimes: const [DoseTime(hour: 8, minute: 0)],
        weekdays: const [DateTime.saturday],
        stock: 4,
        refillThreshold: 1,
      );

      await therapyService.saveTreatment(treatment);
      final loaded = (await therapyService.loadTreatments())
          .firstWhere((t) => t.id == 'treat-weekly');

      expect(loaded.frequency, TreatmentFrequency.weekly);
      expect(loaded.weekdays, [DateTime.saturday]);
      // A regra de agendamento vem inteira do banco: sábado agenda, sexta não.
      expect(loaded.isScheduledOn(DateTime(2026, 11, 7)), isTrue); // sáb
      expect(loaded.isScheduledOn(DateTime(2026, 11, 6)), isFalse); // sex
    });

    test('DoctorStorageService and ConsultationStorageService persist and delete records', () async {
      const doctor = Doctor(
        id: 'doc-1',
        name: 'Dr. Roberto Santos',
        specialty: 'Cardiologia',
        crm: '123456',
        crmState: 'SP',
      );

      await doctorService.saveDoctor(doctor);
      var doctors = await doctorService.loadDoctors();
      expect(doctors.length, 1);
      expect(doctors.first.name, 'Dr. Roberto Santos');

      final consultation = Consultation(
        id: 'cons-1',
        doctorId: 'doc-1',
        date: DateTime.utc(2026, 10, 15, 14, 30),
        title: 'Rotina Semestral',
        notes: 'Levar exames anteriores',
      );

      await consultationService.saveConsultation(consultation);
      var consultations = await consultationService.loadConsultations();
      expect(consultations.length, 1);
      expect(consultations.first.title, 'Rotina Semestral');

      // Test delete
      await consultationService.deleteConsultation('cons-1');
      consultations = await consultationService.loadConsultations();
      expect(consultations, isEmpty);

      await doctorService.deleteDoctor('doc-1');
      doctors = await doctorService.loadDoctors();
      expect(doctors, isEmpty);
    });

    test('Tratamento com prescritor persiste e recarrega quem receitou', () async {
      final treatment = Treatment(
        id: 'treat-presc',
        name: 'Losartana',
        dosage: '50mg',
        presentation: 'Comprimido',
        instructions: '',
        startDate: DateTime(2026, 11, 1, 8, 0),
        endDate: null,
        frequency: TreatmentFrequency.daily,
        doseTimes: const [DoseTime(hour: 8, minute: 0)],
        stock: 30,
        refillThreshold: 5,
        prescriberDoctorId: 'doc-7',
        prescriberName: 'Dr. Carlos Almeida',
        prescriberCrm: '123456',
        prescriberCrmState: 'SP',
        prescribedOn: DateTime(2026, 11, 15),
      );

      await therapyService.saveTreatment(treatment);
      final loaded = (await therapyService.loadTreatments())
          .firstWhere((t) => t.id == 'treat-presc');

      expect(loaded.hasPrescriber, isTrue);
      expect(loaded.prescriberDoctorId, 'doc-7');
      expect(loaded.prescriberName, 'Dr. Carlos Almeida');
      expect(loaded.prescriberCrm, '123456');
      expect(loaded.prescriberCrmState, 'SP');
      expect(loaded.prescribedOn, DateTime(2026, 11, 15));

      // Salvar de novo sem prescritor limpa o snapshot (fonte de verdade
      // é o formulário), mas o histórico abaixo não é apagado.
      await therapyService.saveTreatment(
        treatment.copyWith(clearPrescriber: true, clearPrescribedOn: true),
      );
      final cleared = (await therapyService.loadTreatments())
          .firstWhere((t) => t.id == 'treat-presc');
      expect(cleared.hasPrescriber, isFalse);
    });

    test('Registros de receita: insert append-only e carga por tratamento',
        () async {
      await therapyService.saveTreatment(Treatment(
        id: 'treat-rec',
        name: 'Metotrexato',
        dosage: '15MG',
        presentation: 'Comprimido',
        instructions: '',
        startDate: DateTime(2026, 1, 1, 8, 0),
        endDate: null,
        frequency: TreatmentFrequency.weekly,
        doseTimes: const [DoseTime(hour: 8, minute: 0)],
        weekdays: const [DateTime.saturday],
        stock: null,
        refillThreshold: null,
      ));

      final old = PrescriptionRecord(
        id: 'rec-old',
        treatmentId: 'treat-rec',
        doctorName: 'Dra. Ana Prado',
        doctorCrm: '654321',
        doctorCrmState: 'SP',
        prescribedOn: DateTime(2026, 2, 10),
        source: PrescriptionSource.manual,
        createdAt: DateTime(2026, 2, 10, 9),
      );
      final renewal = PrescriptionRecord(
        id: 'rec-new',
        treatmentId: 'treat-rec',
        doctorName: 'Dr. Carlos Almeida',
        doctorCrm: '123456',
        doctorCrmState: 'SP',
        prescribedOn: DateTime(2026, 11, 15),
        source: PrescriptionSource.prescriptionPhoto,
        createdAt: DateTime(2026, 11, 15, 10),
      );

      await therapyService.insertPrescriptionRecord(old);
      await therapyService.insertPrescriptionRecord(renewal);

      final all = await therapyService.loadPrescriptionRecords();
      expect(all.length, 2);
      // Mais recente primeiro — a receita atual vem antes da antiga.
      expect(all.first.id, 'rec-new');
      expect(all.last.id, 'rec-old');

      final forTreatment = await therapyService.loadPrescriptionRecords(
        treatmentId: 'treat-rec',
      );
      expect(forTreatment.length, 2);
      expect(
        await therapyService.loadPrescriptionRecords(treatmentId: 'outro'),
        isEmpty,
      );

      // O registro carregado preserva quem, quando e de onde veio.
      expect(forTreatment.first.doctorName, 'Dr. Carlos Almeida');
      expect(forTreatment.first.source, PrescriptionSource.prescriptionPhoto);
      expect(forTreatment.first.prescribedOn, DateTime(2026, 11, 15));
    });

    test('Migração v10 → v11: colunas de prescritor e tabela de receitas',
        () async {
      // Arquivo próprio: :memory: é compartilhado pelo ffi e já teria o
      // schema v11 do setUp — a trilha legida precisa de um banco limpo.
      final legacyPath =
          '${Directory.systemTemp.createTempSync('legacy_db').path}/v10.db';
      final db = await openDatabase(
        legacyPath,
        version: 10,
        onCreate: (newDb, version) async {
          // Schema EXATO da v10: treatments sem colunas de prescritor e
          // sem treatment_prescriptions — o estado dos usuários atuais.
          await newDb.execute('''
            CREATE TABLE treatments (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              dosage TEXT NOT NULL DEFAULT '',
              presentation TEXT NOT NULL DEFAULT '',
              instructions TEXT NOT NULL DEFAULT '',
              start_date TEXT NOT NULL,
              end_date TEXT,
              frequency TEXT NOT NULL,
              dose_times TEXT NOT NULL,
              weekdays TEXT,
              stock INTEGER,
              refill_threshold INTEGER,
              is_archived INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          await newDb.insert('treatments', {
            'id': 'legacy-1',
            'name': 'Dipirona',
            'dosage': '500mg',
            'presentation': 'Comprimido',
            'instructions': '',
            'start_date': '2026-01-01T08:00:00.000Z',
            'frequency': 'daily',
            'dose_times': '[]',
            'is_archived': 0,
            'created_at': '2026-01-01T00:00:00.000Z',
            'updated_at': '2026-01-01T00:00:00.000Z',
          });
        },
      );

      // A trilha real de upgrade do DatabaseService (mesmo SQL do app).
      await dbService.applyUpgradesForTesting(db, 10);

      final columns = await db.rawQuery('PRAGMA table_info(treatments)');
      final names = columns.map((column) => column['name']).toList();
      for (final expected in [
        'prescriber_doctor_id',
        'prescriber_name',
        'prescriber_crm',
        'prescriber_crm_state',
        'prescribed_on',
      ]) {
        expect(names, contains(expected), reason: 'faltou coluna $expected');
      }

      // Dado antigo sobrevive e carrega sem prescritor.
      final legacy = await db.query(
        'treatments',
        where: 'id = ?',
        whereArgs: ['legacy-1'],
      );
      expect(legacy, hasLength(1));
      expect(legacy.first['prescriber_name'], isNull);

      // O histórico de receitas existe e aceita registros.
      await dbService.setDatabaseForTesting(db);
      await therapyService.insertPrescriptionRecord(PrescriptionRecord(
        id: 'rec-migrated',
        treatmentId: 'legacy-1',
        doctorName: 'Dr. Carlos Almeida',
        prescribedOn: DateTime(2026, 11, 15),
        createdAt: DateTime(2026, 11, 15),
      ));
      final records = await therapyService.loadPrescriptionRecords(
        treatmentId: 'legacy-1',
      );
      expect(records, hasLength(1));
      expect(records.first.doctorName, 'Dr. Carlos Almeida');

      await db.close();
    });
  });
}
