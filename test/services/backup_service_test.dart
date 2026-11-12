import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:remedios_app_flutter/models/consultation.dart';
import 'package:remedios_app_flutter/models/doctor.dart';
import 'package:remedios_app_flutter/models/dose_event.dart';
import 'package:remedios_app_flutter/models/emergency_contact.dart';
import 'package:remedios_app_flutter/models/health_plan.dart';
import 'package:remedios_app_flutter/models/treatment.dart';
import 'package:remedios_app_flutter/models/user_profile.dart';
import 'package:remedios_app_flutter/providers/user_profile_provider.dart';
import 'package:remedios_app_flutter/services/backup_service.dart';
import 'package:remedios_app_flutter/services/consultation_storage_service.dart';
import 'package:remedios_app_flutter/services/database_service.dart';
import 'package:remedios_app_flutter/services/doctor_storage_service.dart';
import 'package:remedios_app_flutter/services/health_plan_storage_service.dart';
import 'package:remedios_app_flutter/services/therapy_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DatabaseService dbService;
  late TherapyStorageService therapyService;
  late DoctorStorageService doctorService;
  late ConsultationStorageService consultationService;
  late HealthPlanStorageService healthPlanService;
  late UserProfileProvider profileProvider;
  late BackupService backupService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // O singleton mantém o :memory: aberto entre testes — fechar para cada
    // teste começar com um banco realmente vazio.
    await DatabaseService.instance.close();
    dbService = DatabaseService.instance;
    await dbService.initInMemoryDatabase();

    therapyService = TherapyStorageService(dbService: dbService);
    doctorService = DoctorStorageService(dbService: dbService);
    consultationService = ConsultationStorageService(dbService: dbService);
    healthPlanService = HealthPlanStorageService(dbService: dbService);
    profileProvider = UserProfileProvider(dbService: dbService);
    backupService = BackupService(dbService: dbService);
  });

  Treatment buildTreatment({
    String id = 'treat-1',
    TreatmentFrequency frequency = TreatmentFrequency.daily,
    List<int> weekdays = const [],
  }) {
    return Treatment(
      id: id,
      name: 'Amoxicilina',
      dosage: '500mg',
      presentation: 'Cápsula',
      instructions: 'Tomar após as refeições',
      startDate: DateTime(2026, 11, 1, 8, 0),
      endDate: DateTime(2026, 11, 30, 8, 0),
      frequency: frequency,
      doseTimes: const [DoseTime(hour: 8, minute: 0)],
      weekdays: weekdays,
      stock: 14,
      refillThreshold: 4,
    );
  }

  /// Semeia um registro em cada tabela, incluindo um tratamento semanal
  /// (a coluna `weekdays` é a mais delicada do round-trip).
  Future<void> seedAll() async {
    await therapyService.saveTreatment(buildTreatment());
    await therapyService.saveTreatment(buildTreatment(
      id: 'treat-weekly',
      frequency: TreatmentFrequency.weekly,
      weekdays: const [DateTime.saturday],
    ));
    await therapyService.saveDoseEvent(DoseEvent(
      id: 'dose-1',
      treatmentId: 'treat-1',
      scheduledAt: DateTime.utc(2026, 11, 12, 8, 0),
      status: DoseStatus.taken,
      completedAt: DateTime.utc(2026, 11, 12, 8, 5),
    ));

    const doctor = Doctor(
      id: 'doc-1',
      name: 'Dra. Ana Prado',
      specialty: 'Cardiologia',
      crm: '123456',
      crmState: 'SP',
      phone: '(11) 3232-1010',
      city: 'São Paulo',
    );
    await doctorService.saveDoctor(doctor);
    await consultationService.saveConsultation(Consultation(
      id: 'cons-1',
      doctorId: 'doc-1',
      date: DateTime.utc(2026, 12, 1, 14, 30),
      title: 'Retorno cardiológico',
    ));

    await healthPlanService.saveHealthPlan(HealthPlan(
      id: 'plan-1',
      name: 'Unimed Nacional',
      provider: 'Unimed',
      cardNumber: '0011223344',
      specialties: const ['Cardiologia', 'Clínica geral'],
      createdAt: DateTime.now().toUtc().toIso8601String(),
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    ));

    await profileProvider.saveProfile(UserProfile(
      nome: 'Alex Silva',
      alergias: const ['penicilina'],
      createdAt: DateTime.now().toUtc().toIso8601String(),
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    ));
    await profileProvider.addEmergencyContact(EmergencyContact(
      id: 'ec-1',
      nome: 'Maria Silva',
      parentesco: 'Esposa',
      telefone: '(11) 98888-7777',
    ));
  }

  /// Limpa todas as tabelas (simula "perder o dispositivo").
  Future<void> wipeAll() async {
    final db = await dbService.database;
    await db.transaction((txn) async {
      for (final table in [
        'dose_events',
        'consultations',
        'emergency_contacts',
        'user_profile',
        'health_plans',
        'doctors',
        'treatments',
      ]) {
        await txn.delete(table);
      }
    });
  }

  group('BackupService', () {
    test('exportAll devolve estrutura completa com todas as tabelas',
        () async {
      await seedAll();
      final backup = await backupService.exportAll();

      expect(backup['app'], BackupService.appMarker);
      expect(backup['formatVersion'], BackupService.backupFormatVersion);
      expect(backup['schemaVersion'], BackupService.maxSchemaVersion);
      expect(backup['exportedAt'], isA<String>());

      final tables = backup['tables'] as Map<String, dynamic>;
      expect(tables.keys, containsAll([
        'treatments',
        'dose_events',
        'doctors',
        'consultations',
        'health_plans',
        'user_profile',
        'emergency_contacts',
      ]));
      expect(tables['treatments'], hasLength(2));
      expect(tables['dose_events'], hasLength(1));
      expect(tables['doctors'], hasLength(1));
      expect(tables['consultations'], hasLength(1));
      expect(tables['health_plans'], hasLength(1));
      expect(tables['user_profile'], hasLength(1));
      expect(tables['emergency_contacts'], hasLength(1));
    });

    test('restore recria tudo após limpar o banco (round-trip)', () async {
      await seedAll();
      final backup = await backupService.exportAll();
      await wipeAll();

      // Confirma que o banco está realmente vazio.
      final emptyTreatments = await therapyService.loadTreatments();
      expect(emptyTreatments, isEmpty);

      final summary = await backupService.restore(backup);
      expect(summary.treatments, 2);
      expect(summary.doseEvents, 1);
      expect(summary.doctors, 1);
      expect(summary.consultations, 1);
      expect(summary.healthPlans, 1);
      expect(summary.hasUserProfile, isTrue);
      expect(summary.emergencyContacts, 1);
      expect(summary.describe(),
          '2 tratamentos, 1 doses, 1 médicos, 1 consultas, 1 planos, perfil, '
          '1 contatos de emergência');

      // Tudo volta, incluindo a parte mais delicada: o semanal.
      final treatments = await therapyService.loadTreatments();
      expect(treatments, hasLength(2));
      final weekly = treatments.firstWhere((t) => t.id == 'treat-weekly');
      expect(weekly.frequency, TreatmentFrequency.weekly);
      expect(weekly.weekdays, [DateTime.saturday]);
      expect(weekly.isScheduledOn(DateTime(2026, 11, 7)), isTrue);

      final doses = await therapyService.loadDoseEvents();
      expect(doses, hasLength(1));
      expect(doses.first.status, DoseStatus.taken);

      final doctors = await doctorService.loadDoctors();
      expect(doctors.single.name, 'Dra. Ana Prado');

      final consultations = await consultationService.loadConsultations();
      expect(consultations.single.title, 'Retorno cardiológico');
      expect(consultations.single.doctorId, 'doc-1');

      final plans = await healthPlanService.loadHealthPlans();
      expect(plans.single.cardNumber, '0011223344');
      expect(plans.single.specialties, ['Cardiologia', 'Clínica geral']);

      await profileProvider.initialize();
      expect(profileProvider.profile?.nome, 'Alex Silva');
      expect(profileProvider.emergencyContacts.single.nome, 'Maria Silva');
    });

    test('export → restore → export é idempotente', () async {
      await seedAll();
      final first = await backupService.exportAll();
      await backupService.restore(first);
      final second = await backupService.exportAll();

      // O único campo que pode diferir é o carimbo de hora da exportação.
      (first['tables'] as Map).remove('exportedAt');
      expect(second['tables'], first['tables']);
      expect(second['schemaVersion'], first['schemaVersion']);
      expect(second['formatVersion'], first['formatVersion']);
    });

    test('arquivo que não é um backup do app é rejeitado', () async {
      expect(
        () => backupService.restore({'tables': {}}),
        throwsA(isA<BackupFormatException>()),
      );
      expect(
        () => backupService
            .restore({'app': 'outro-app', 'tables': {}}),
        throwsA(isA<BackupFormatException>()),
      );
      expect(
        () => backupService.restore(jsonDecode(
            '{"app": "remedios-app", "formatVersion": 1, '
            '"schemaVersion": 99, "tables": {}}') as Map<String, dynamic>),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('backup de formato mais novo que o app é rejeitado', () async {
      expect(
        () => backupService.restore(jsonDecode(
            '{"app": "remedios-app", "formatVersion": 2, '
            '"schemaVersion": 7, "tables": {}}') as Map<String, dynamic>),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('linha sem chave de integridade é rejeitada', () async {
      final backup = {
        'app': BackupService.appMarker,
        'formatVersion': BackupService.backupFormatVersion,
        'schemaVersion': BackupService.maxSchemaVersion,
        'tables': {
          'dose_events': [
            {'id': 'dose-sem-tratamento'},
          ],
        },
      };
      expect(
        () => backupService.restore(backup),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('tabela ausente no backup restaura vazia (compatibilidade)',
        () async {
      final backup = {
        'app': BackupService.appMarker,
        'formatVersion': BackupService.backupFormatVersion,
        'schemaVersion': BackupService.maxSchemaVersion,
        'tables': {
          'treatments': [
            {
              'id': 'treat-1',
              'name': 'Losartana',
              'dosage': '50mg',
              'presentation': 'Comprimido',
              'instructions': 'Tomar 1 comprimido ao dia',
              'start_date': DateTime.utc(2026, 11, 1, 8).toIso8601String(),
              'end_date': null,
              'frequency': 'daily',
              'dose_times': '[{"hour":8,"minute":0}]',
              'is_archived': 0,
              'created_at': DateTime.utc(2026, 11, 1).toIso8601String(),
              'updated_at': DateTime.utc(2026, 11, 1).toIso8601String(),
            },
          ],
        },
      };
      await wipeAll();
      final summary = await backupService.restore(backup);
      expect(summary.treatments, 1);
      expect(summary.doseEvents, 0);
      expect(summary.doctors, 0);

      final treatments = await therapyService.loadTreatments();
      expect(treatments.single.name, 'Losartana');
    });
  });
}
