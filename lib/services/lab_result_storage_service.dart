import 'package:sqflite/sqflite.dart';

import '../models/lab_result.dart';
import 'database_service.dart';

/// Persistência dos laudos de laboratório (SQLite). Os valores por
/// marcador ficam em values_json; as flags são recalculadas no app ao
/// ler (a IA nunca classifica resultado).
class LabResultStorageService {
  LabResultStorageService({DatabaseService? dbService})
    : _dbService = dbService ?? DatabaseService.instance;

  final DatabaseService _dbService;

  Future<List<LabResult>> loadResults() async {
    final db = await _dbService.database;
    final rows = await db.query('lab_results', orderBy: 'date DESC');

    return rows.map((row) {
      final dateUtc = DateTime.parse(row['date'] as String);
      final createdAtRaw = row['created_at'] as String?;

      return LabResult(
        id: row['id'] as String,
        date: dateUtc.toLocal(),
        labName: row['lab_name'] as String? ?? '',
        photo: row['photo'] as String?,
        values: LabResult.valuesFromJsonText(row['values_json'] as String?),
        notes: row['notes'] as String? ?? '',
        createdAt: createdAtRaw != null ? DateTime.parse(createdAtRaw) : null,
      );
    }).toList();
  }

  Future<void> saveResult(LabResult result) async {
    final db = await _dbService.database;
    final nowIso = DateTime.now().toUtc().toIso8601String();

    await db.insert(
      'lab_results',
      _rowOf(result, nowIso),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveResults(List<LabResult> results) async {
    final db = await _dbService.database;
    final batch = db.batch();
    final nowIso = DateTime.now().toUtc().toIso8601String();

    for (final result in results) {
      batch.insert(
        'lab_results',
        _rowOf(result, nowIso),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> deleteResult(String id) async {
    final db = await _dbService.database;
    await db.delete('lab_results', where: 'id = ?', whereArgs: [id]);
  }

  Map<String, Object?> _rowOf(LabResult result, String nowIso) => {
    'id': result.id,
    'date': result.date.toUtc().toIso8601String(),
    'lab_name': result.labName,
    'photo': result.photo,
    'values_json': result.valuesJson,
    'notes': result.notes,
    'created_at': result.createdAt?.toUtc().toIso8601String() ?? nowIso,
    'updated_at': nowIso,
  };
}
