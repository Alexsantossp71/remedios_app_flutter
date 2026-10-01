import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:remedios_app_flutter/models/consultation.dart';
import 'package:remedios_app_flutter/models/doctor.dart';
import 'package:remedios_app_flutter/models/dose_event.dart';
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
  });
}
