import 'package:sqflite/sqflite.dart';

import '../models/exam.dart';
import 'database_service.dart';

/// Persistência dos exames (SQLite). A foto segue embutida na própria
/// linha (base64 JPEG) — mesma decisão do PWA, sem novo arquivo no disco.
class ExamStorageService {
  ExamStorageService({DatabaseService? dbService})
      : _dbService = dbService ?? DatabaseService.instance;

  final DatabaseService _dbService;

  Future<List<Exam>> loadExams() async {
    final db = await _dbService.database;
    final rows = await db.query('exams', orderBy: 'date ASC');

    return rows.map((row) {
      final dateUtc = DateTime.parse(row['date'] as String);
      final createdAtRaw = row['created_at'] as String?;

      return Exam(
        id: row['id'] as String,
        name: row['name'] as String,
        category: row['category'] as String? ?? '',
        status: row['status'] as String? ?? ExamStatus.requested,
        date: dateUtc.toLocal(),
        time: row['time'] as String?,
        photo: row['photo'] as String?,
        doctorId: row['doctor_id'] as String? ?? '',
        doctorName: row['doctor_name'] as String? ?? '',
        place: row['place'] as String? ?? '',
        results: row['results'] as String? ?? '',
        createdAt:
            createdAtRaw != null ? DateTime.parse(createdAtRaw) : null,
      );
    }).toList();
  }

  Future<void> saveExam(Exam exam) async {
    final db = await _dbService.database;
    final nowIso = DateTime.now().toUtc().toIso8601String();

    await db.insert(
      'exams',
      _rowOf(exam, nowIso),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveExams(List<Exam> exams) async {
    final db = await _dbService.database;
    final batch = db.batch();
    final nowIso = DateTime.now().toUtc().toIso8601String();

    for (final exam in exams) {
      batch.insert(
        'exams',
        _rowOf(exam, nowIso),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> deleteExam(String id) async {
    final db = await _dbService.database;
    await db.delete('exams', where: 'id = ?', whereArgs: [id]);
  }

  Map<String, Object?> _rowOf(Exam exam, String nowIso) => {
        'id': exam.id,
        'name': exam.name,
        'category': exam.category,
        'status': exam.status,
        'date': exam.date.toUtc().toIso8601String(),
        'time': exam.time,
        'photo': exam.photo,
        'doctor_id': exam.doctorId,
        'doctor_name': exam.doctorName,
        'place': exam.place,
        'results': exam.results,
        'created_at': exam.createdAt?.toUtc().toIso8601String() ?? nowIso,
        'updated_at': nowIso,
      };
}
