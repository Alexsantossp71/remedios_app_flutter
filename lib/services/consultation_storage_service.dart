import 'package:sqflite/sqflite.dart';

import '../models/consultation.dart';
import 'database_service.dart';

class ConsultationStorageService {
  final DatabaseService _dbService;

  ConsultationStorageService({DatabaseService? dbService})
      : _dbService = dbService ?? DatabaseService.instance;

  Future<List<Consultation>> loadConsultations() async {
    final db = await _dbService.database;
    final rows = await db.query('consultations', orderBy: 'date ASC');

    return rows.map((row) {
      final dateUtc = DateTime.parse(row['date'] as String);
      final returnDateRaw = row['return_date'] as String?;
      final returnDateUtc =
          returnDateRaw != null ? DateTime.parse(returnDateRaw) : null;
      final completedAtRaw = row['completed_at'] as String?;
      final completedAtUtc =
          completedAtRaw != null ? DateTime.parse(completedAtRaw) : null;

      return Consultation(
        id: row['id'] as String,
        doctorId: row['doctor_id'] as String,
        date: dateUtc.toLocal(),
        title: row['title'] as String? ?? '',
        notes: row['notes'] as String? ?? '',
        status: row['status'] as String? ?? 'scheduled',
        returnDate: returnDateUtc?.toLocal(),
        completedAt: completedAtUtc?.toLocal(),
      );
    }).toList();
  }

  Future<void> saveConsultation(Consultation consultation) async {
    final db = await _dbService.database;
    final nowIso = DateTime.now().toUtc().toIso8601String();

    await db.insert(
      'consultations',
      {
        'id': consultation.id,
        'doctor_id': consultation.doctorId,
        'date': consultation.date.toUtc().toIso8601String(),
        'title': consultation.title,
        'notes': consultation.notes,
        'status': consultation.status,
        'return_date': consultation.returnDate?.toUtc().toIso8601String(),
        'created_at': nowIso,
        'updated_at': nowIso,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveConsultations(List<Consultation> consultations) async {
    final db = await _dbService.database;
    final batch = db.batch();
    final nowIso = DateTime.now().toUtc().toIso8601String();

    for (final consultation in consultations) {
      batch.insert(
        'consultations',
        {
          'id': consultation.id,
          'doctor_id': consultation.doctorId,
          'date': consultation.date.toUtc().toIso8601String(),
          'title': consultation.title,
          'notes': consultation.notes,
          'status': consultation.status,
          'return_date': consultation.returnDate?.toUtc().toIso8601String(),
          'created_at': nowIso,
          'updated_at': nowIso,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> deleteConsultation(String id) async {
    final db = await _dbService.database;
    await db.delete('consultations', where: 'id = ?', whereArgs: [id]);
  }
}
