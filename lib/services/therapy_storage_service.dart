import 'dart:convert';
import 'package:sqflite/sqflite.dart';

import '../models/dose_event.dart';
import '../models/prescription_record.dart';
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
        weekdays: (row['weekdays'] == null)
            ? const <int>[]
            : (jsonDecode(row['weekdays'] as String) as List<dynamic>)
                .map((day) => day as int)
                .where((day) => day >= 1 && day <= 7)
                .toList(),
        stock: row['stock'] as int?,
        refillThreshold: row['refill_threshold'] as int?,
        isArchived: (row['is_archived'] as int? ?? 0) == 1,
        prescriberDoctorId: row['prescriber_doctor_id'] as String?,
        prescriberName: row['prescriber_name'] as String? ?? '',
        prescriberCrm: row['prescriber_crm'] as String? ?? '',
        prescriberCrmState: row['prescriber_crm_state'] as String? ?? '',
        prescribedOn: row['prescribed_on'] == null
            ? null
            : DateTime.parse(row['prescribed_on'] as String).toLocal(),
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
        'weekdays': treatment.weekdays.isEmpty
            ? null
            : jsonEncode(treatment.weekdays),
        'stock': treatment.stock,
        'refill_threshold': treatment.refillThreshold,
        'is_archived': treatment.isArchived ? 1 : 0,
        'prescriber_doctor_id': treatment.prescriberDoctorId,
        'prescriber_name':
            treatment.prescriberName.isEmpty ? null : treatment.prescriberName,
        'prescriber_crm':
            treatment.prescriberCrm.isEmpty ? null : treatment.prescriberCrm,
        'prescriber_crm_state': treatment.prescriberCrmState.isEmpty
            ? null
            : treatment.prescriberCrmState,
        'prescribed_on':
            treatment.prescribedOn?.toUtc().toIso8601String(),
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
          'weekdays': treatment.weekdays.isEmpty
              ? null
              : jsonEncode(treatment.weekdays),
          'stock': treatment.stock,
          'refill_threshold': treatment.refillThreshold,
          'is_archived': treatment.isArchived ? 1 : 0,
          'prescriber_doctor_id': treatment.prescriberDoctorId,
          'prescriber_name':
              treatment.prescriberName.isEmpty
                  ? null
                  : treatment.prescriberName,
          'prescriber_crm':
              treatment.prescriberCrm.isEmpty ? null : treatment.prescriberCrm,
          'prescriber_crm_state': treatment.prescriberCrmState.isEmpty
              ? null
              : treatment.prescriberCrmState,
          'prescribed_on':
              treatment.prescribedOn?.toUtc().toIso8601String(),
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

  /// Histórico de "quem receitou e em que dia". Sem [treatmentId], devolve
  /// todos os registros; com, só os daquele tratamento (mais recente
  /// primeiro — a receita atual vem antes das antigas).
  Future<List<PrescriptionRecord>> loadPrescriptionRecords({
    String? treatmentId,
  }) async {
    final db = await _dbService.database;
    final rows = await db.query(
      'treatment_prescriptions',
      where: treatmentId == null ? null : 'treatment_id = ?',
      whereArgs: treatmentId == null ? null : [treatmentId],
      orderBy: 'prescribed_on DESC, created_at DESC',
    );

    return rows.map((row) {
      return PrescriptionRecord(
        id: row['id'] as String,
        treatmentId: row['treatment_id'] as String,
        doctorId: row['doctor_id'] as String?,
        doctorName: row['doctor_name'] as String? ?? '',
        doctorCrm: row['doctor_crm'] as String? ?? '',
        doctorCrmState: row['doctor_crm_state'] as String? ?? '',
        prescribedOn:
            DateTime.parse(row['prescribed_on'] as String).toLocal(),
        source: PrescriptionSource.fromName(row['source'] as String?),
        createdAt:
            DateTime.parse(row['created_at'] as String).toLocal(),
      );
    }).toList();
  }

  /// Grava um novo registro de receita. NUNCA usa replace: cada chamada é
  /// uma renovação e o histórico é só-append — sobrescrever apagaria a
  /// memória de quem receitou antes.
  Future<void> insertPrescriptionRecord(PrescriptionRecord record) async {
    final db = await _dbService.database;
    await db.insert('treatment_prescriptions', {
      'id': record.id,
      'treatment_id': record.treatmentId,
      'doctor_id': record.doctorId,
      'doctor_name': record.doctorName,
      'doctor_crm': record.doctorCrm.isEmpty ? null : record.doctorCrm,
      'doctor_crm_state':
          record.doctorCrmState.isEmpty ? null : record.doctorCrmState,
      'prescribed_on': record.prescribedOn.toUtc().toIso8601String(),
      'source': record.source.name,
      'created_at': record.createdAt.toUtc().toIso8601String(),
    });
  }

  }
