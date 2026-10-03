import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/health_plan.dart';
import 'database_service.dart';

/// Storage service for HealthPlan entities.
/// Handles CRUD operations with SQLite persistence.
class HealthPlanStorageService {
  final DatabaseService _dbService;

  HealthPlanStorageService({DatabaseService? dbService})
      : _dbService = dbService ?? DatabaseService.instance;

  /// Loads all health plans from the database, ordered by name.
  Future<List<HealthPlan>> loadHealthPlans() async {
    final db = await _dbService.database;
    final rows = await db.query('health_plans', orderBy: 'name ASC');

    return rows.map((row) => _rowToHealthPlan(row)).toList();
  }

  /// Saves a health plan to the database (insert or update).
  Future<void> saveHealthPlan(HealthPlan plan) async {
    final db = await _dbService.database;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.insert(
      'health_plans',
      {
        'id': plan.id,
        'name': plan.name,
        'provider': plan.provider,
        'card_number': plan.cardNumber ?? '',
        'group_number': plan.groupNumber ?? '',
        'beneficiary_code': plan.beneficiaryCode ?? '',
        'validity': plan.validity ?? '',
        'coverage_type': plan.coverageType ?? '',
        'specialties': jsonEncode(plan.specialties),
        'notes': plan.notes ?? '',
        'created_at': plan.createdAt,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Saves multiple health plans in a batch operation.
  Future<void> saveHealthPlans(List<HealthPlan> plans) async {
    final db = await _dbService.database;
    final batch = db.batch();
    final now = DateTime.now().toUtc().toIso8601String();

    for (final plan in plans) {
      batch.insert(
        'health_plans',
        {
          'id': plan.id,
          'name': plan.name,
          'provider': plan.provider,
          'card_number': plan.cardNumber ?? '',
          'group_number': plan.groupNumber ?? '',
          'beneficiary_code': plan.beneficiaryCode ?? '',
          'validity': plan.validity ?? '',
          'coverage_type': plan.coverageType ?? '',
          'specialties': jsonEncode(plan.specialties),
          'notes': plan.notes ?? '',
          'created_at': plan.createdAt,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  /// Deletes a health plan by ID.
  Future<void> deleteHealthPlan(String id) async {
    final db = await _dbService.database;
    await db.delete('health_plans', where: 'id = ?', whereArgs: [id]);
  }

  /// Gets a single health plan by ID.
  Future<HealthPlan?> getHealthPlan(String id) async {
    final db = await _dbService.database;
    final rows = await db.query(
      'health_plans',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return _rowToHealthPlan(rows.first);
  }

  /// Searches health plans by name or provider.
  Future<List<HealthPlan>> search(String query) async {
    final plans = await loadHealthPlans();
    if (query.isEmpty) return plans;

    final normalizedQuery = query.trim().toLowerCase();
    return plans.where((plan) {
      return plan.name.toLowerCase().contains(normalizedQuery) ||
          plan.provider.toLowerCase().contains(normalizedQuery) ||
          (plan.cardNumber?.contains(query) ?? false);
    }).toList();
  }

  /// Converts a database row to a HealthPlan instance.
  HealthPlan _rowToHealthPlan(Map<String, dynamic> row) {
    final rawSpecialties = row['specialties'] as String? ?? '[]';
    var specialties = <String>[];
    try {
      specialties = (jsonDecode(rawSpecialties) as List)
          .map((e) => e as String)
          .toList();
    } catch (_) {
      // Keep empty list when specialties payload is malformed.
    }

    return HealthPlan(
      id: row['id'] as String,
      name: row['name'] as String,
      provider: row['provider'] as String,
      cardNumber: (row['card_number'] as String?)?.isNotEmpty == true
          ? row['card_number'] as String
          : null,
      groupNumber: (row['group_number'] as String?)?.isNotEmpty == true
          ? row['group_number'] as String
          : null,
      beneficiaryCode: (row['beneficiary_code'] as String?)?.isNotEmpty == true
          ? row['beneficiary_code'] as String
          : null,
      validity: (row['validity'] as String?)?.isNotEmpty == true
          ? row['validity'] as String
          : null,
      coverageType: (row['coverage_type'] as String?)?.isNotEmpty == true
          ? row['coverage_type'] as String
          : null,
      specialties: specialties,
      notes: (row['notes'] as String?)?.isNotEmpty == true
          ? row['notes'] as String
          : null,
      createdAt: row['created_at'] as String,
      updatedAt: row['updated_at'] as String,
    );
  }
}