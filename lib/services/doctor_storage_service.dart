import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/doctor.dart';
import 'database_service.dart';

class DoctorStorageService {
  final DatabaseService _dbService;

  DoctorStorageService({DatabaseService? dbService})
      : _dbService = dbService ?? DatabaseService.instance;

  Future<List<Doctor>> loadDoctors() async {
    final db = await _dbService.database;
    final rows = await db.query('doctors', orderBy: 'name ASC');

    return rows.map((row) {
      return Doctor(
        id: row['id'] as String,
        name: row['name'] as String? ?? '',
        specialty: row['specialty'] as String? ?? '',
        crm: row['crm'] as String? ?? '',
        crmState: row['crm_state'] as String? ?? '',
        phone: row['phone'] as String? ?? '',
        email: row['email'] as String? ?? '',
        clinic: row['clinic'] as String? ?? '',
        street: row['street'] as String? ?? '',
        number: row['number'] as String? ?? '',
        complement: row['complement'] as String? ?? '',
        neighborhood: row['neighborhood'] as String? ?? '',
        city: row['city'] as String? ?? '',
        state: row['state'] as String? ?? '',
        postalCode: row['postal_code'] as String? ?? '',
        healthPlans: row['health_plans'] as String? ?? '',
        notes: row['notes'] as String? ?? '',
      );
    }).toList();
  }

  Future<void> saveDoctor(Doctor doctor) async {
    final db = await _dbService.database;
    final nowIso = DateTime.now().toUtc().toIso8601String();

    await db.insert(
      'doctors',
      {
        'id': doctor.id,
        'name': doctor.name,
        'specialty': doctor.specialty,
        'crm': doctor.crm,
        'crm_state': doctor.crmState,
        'phone': doctor.phone,
        'email': doctor.email,
        'clinic': doctor.clinic,
        'street': doctor.street,
        'number': doctor.number,
        'complement': doctor.complement,
        'neighborhood': doctor.neighborhood,
        'city': doctor.city,
        'state': doctor.state,
        'postal_code': doctor.postalCode,
        'health_plans': doctor.healthPlans,
        'notes': doctor.notes,
        'created_at': nowIso,
        'updated_at': nowIso,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveDoctors(List<Doctor> doctors) async {
    final db = await _dbService.database;
    final batch = db.batch();
    final nowIso = DateTime.now().toUtc().toIso8601String();

    for (final doctor in doctors) {
      batch.insert(
        'doctors',
        {
          'id': doctor.id,
          'name': doctor.name,
          'specialty': doctor.specialty,
          'crm': doctor.crm,
          'crm_state': doctor.crmState,
          'phone': doctor.phone,
          'email': doctor.email,
          'clinic': doctor.clinic,
          'street': doctor.street,
          'number': doctor.number,
          'complement': doctor.complement,
          'neighborhood': doctor.neighborhood,
          'city': doctor.city,
          'state': doctor.state,
          'postal_code': doctor.postalCode,
          'health_plans': doctor.healthPlans,
          'notes': doctor.notes,
          'created_at': nowIso,
          'updated_at': nowIso,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> deleteDoctor(String id) async {
    final db = await _dbService.database;
    await db.delete('doctors', where: 'id = ?', whereArgs: [id]);
  }
}
