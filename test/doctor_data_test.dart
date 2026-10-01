import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:remedios_app_flutter/models/doctor.dart';
import 'package:remedios_app_flutter/providers/doctor_provider.dart';
import 'package:remedios_app_flutter/services/database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DatabaseService.instance.initInMemoryDatabase();
  });

  test('doctor retains useful directory details when serialized', () {
    const doctor = Doctor(
      id: 'doctor-1',
      name: 'Dra. Ana Silva',
      specialty: 'Cardiologia',
      crm: '12345',
      crmState: 'sp',
      phone: '(11) 99999-0000',
      clinic: 'Clínica Central',
      street: 'Rua das Flores',
      number: '120',
      city: 'São Paulo',
      state: 'SP',
      postalCode: '01000-000',
      healthPlans: 'Plano Vida',
    );

    final restored = Doctor.fromJson(doctor.toJson());

    expect(restored.name, doctor.name);
    expect(restored.crmLabel, 'CRM 12345/SP');
    expect(restored.fullAddress, contains('Rua das Flores, 120'));
    expect(restored.healthPlans, doctor.healthPlans);
  });

  test('provider persists doctors and searches all directory fields', () async {
    final provider = DoctorProvider();
    await provider.initialize();
    await provider.saveDoctor(
      const Doctor(
        id: 'doctor-1',
        name: 'Ana Silva',
        specialty: 'Cardiologia',
        crm: '12345',
        crmState: 'SP',
        city: 'São Paulo',
      ),
    );

    expect(provider.search('12345'), hasLength(1));
    expect(provider.search('cardio', specialty: 'Cardiologia'), hasLength(1));
    expect(provider.search('pediatria'), isEmpty);

    final reloaded = DoctorProvider();
    await reloaded.initialize();
    expect(reloaded.doctors.single.name, 'Ana Silva');

    await reloaded.removeDoctor('doctor-1');
    expect(reloaded.doctors, isEmpty);
  });
}
