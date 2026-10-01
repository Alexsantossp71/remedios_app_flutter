import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/dose_event.dart';
import '../models/treatment.dart';
import 'database_service.dart';

class TherapyStorageService {
  final DatabaseService _dbService;

  TherapyStorageService({DatabaseService? dbService})
      : _dbService = dbService ?? DatabaseService.instance;

  Future<List<Treatment>> loadTreatments() async {
    final db = await _dbService.database;
    final rows = await db.query('treatments', orderBy: 'name ASC');

    return rows.map((row) {
      final doseTimesRaw = jsonDecode(row['dose_times'] as String) as List<dynamic>;
      final doseTimes = doseTimesRaw
          .map((item) => DoseTime.fromJson(item as Map<String, dynamic>))
          .toList();

      final startDateUtc = DateTime.parse(row['start_date'] as String);
      final endDateRaw = row['end_date'] as String?;
      final endDateUtc = endDateRaw != null ? DateTime.parse(endDateRaw) : null;

      return Treatment(
        id: row['id'] as String,
        name: row['name'] as String,
        dosage: row['dosage'] as String? ?? '',
        presentation: row['presentation'] as String? ?? '',
        instructions: row['instructions'] as String? ?? '',
        startDate: startDateUtc.toLocal(),
        endDate: endDateUtc?.toLocal(),
        frequency: TreatmentFrequency.values.byName(
          row['frequency'] as String? ?? TreatmentFrequency.daily.name,
        ),
        doseTimes: doseTimes,
        stock: row['stock'] as int?,
        refillThreshold: row['refill_threshold'] as int?,
        isArchived: (row['is_archived'] as int? ?? 0) == 1,
      );
    }).toList();
  }

  Future<List<DoseEvent>> loadDoseEvents() async {
    final db = await _dbService.database;
    final rows = await db.query('dose_events', orderBy: 'scheduled_at ASC');

    return rows.map((row) {
      final scheduledAtUtc = DateTime.parse(row['scheduled_at'] as String);
      final completedAtRaw = row['completed_at'] as String?;
      final completedAtUtc =
          completedAtRaw != null ? DateTime.parse(completedAtRaw) : null;

      return DoseEvent(
        id: row['id'] as String,
        treatmentId: row['treatment_id'] as String,
        scheduledAt: scheduledAtUtc.toLocal(),
        status: DoseStatus.values.byName(
          row['status'] as String? ?? DoseStatus.pending.name,
        ),
        completedAt: completedAtUtc?.toLocal(),
      );
    }).toList();
  }

  Future<void> saveTreatment(Treatment treatment) async {
    final db = await _dbService.database;
    final nowIso = DateTime.now().toUtc().toIso8601String();

    await db.insert(
      'treatments',
      {
        'id': treatment.id,
        'name': treatment.name,
        'dosage': treatment.dosage,
        'presentation': treatment.presentation,
        'instructions': treatment.instructions,
        'start_date': treatment.startDate.toUtc().toIso8601String(),
        'end_date': treatment.endDate?.toUtc().toIso8601String(),
        'frequency': treatment.frequency.name,
        'dose_times': jsonEncode(
          treatment.doseTimes.map((t) => t.toJson()).toList(),
        ),
        'stock': treatment.stock,
        'refill_threshold': treatment.refillThreshold,
        'is_archived': treatment.isArchived ? 1 : 0,
        'created_at': nowIso,
        'updated_at': nowIso,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveTreatments(List<Treatment> treatments) async {
    final db = await _dbService.database;
    final batch = db.batch();
    final nowIso = DateTime.now().toUtc().toIso8601String();

    for (final treatment in treatments) {
      batch.insert(
        'treatments',
        {
          'id': treatment.id,
          'name': treatment.name,
          'dosage': treatment.dosage,
          'presentation': treatment.presentation,
          'instructions': treatment.instructions,
          'start_date': treatment.startDate.toUtc().toIso8601String(),
          'end_date': treatment.endDate?.toUtc().toIso8601String(),
          'frequency': treatment.frequency.name,
          'dose_times': jsonEncode(
            treatment.doseTimes.map((t) => t.toJson()).toList(),
          ),
          'stock': treatment.stock,
          'refill_threshold': treatment.refillThreshold,
          'is_archived': treatment.isArchived ? 1 : 0,
          'created_at': nowIso,
          'updated_at': nowIso,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> saveDoseEvent(DoseEvent event) async {
    final db = await _dbService.database;
    final nowIso = DateTime.now().toUtc().toIso8601String();

    await db.insert(
      'dose_events',
      {
        'id': event.id,
        'treatment_id': event.treatmentId,
        'scheduled_at': event.scheduledAt.toUtc().toIso8601String(),
        'status': event.status.name,
        'completed_at': event.completedAt?.toUtc().toIso8601String(),
        'created_at': nowIso,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveDoseEvents(List<DoseEvent> doseEvents) async {
    final db = await _dbService.database;
    final batch = db.batch();
    final nowIso = DateTime.now().toUtc().toIso8601String();

    for (final event in doseEvents) {
      batch.insert(
        'dose_events',
        {
          'id': event.id,
          'treatment_id': event.treatmentId,
          'scheduled_at': event.scheduledAt.toUtc().toIso8601String(),
          'status': event.status.name,
          'completed_at': event.completedAt?.toUtc().toIso8601String(),
          'created_at': nowIso,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  }
