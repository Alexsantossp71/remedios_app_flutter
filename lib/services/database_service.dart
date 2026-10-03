import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Import the correct database factory based on platform.
// On web: uses sqflite_common_ffi_web (IndexedDB + WASM).
// On mobile/desktop: uses sqflite's default implementation.
import 'database_factory_web.dart' if (dart.library.io) 'database_factory_io.dart';

/// Database service for managing SQLite database instance, schemas, and migrations.
class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  static const String _databaseName = 'remedios_app.db';
  static const int _databaseVersion = 3;

  Database? _db;
  bool _isInitialized = false;

  /// Returns the singleton [Database] instance.
  Future<Database> get database async {
    if (_db != null && _db!.isOpen) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  /// Optional override for tests.
  @visibleForTesting
  Future<void> setDatabaseForTesting(Database db) async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
    }
    _db = db;
    _isInitialized = true;
  }

  /// Initialize an in-memory database for testing.
  @visibleForTesting
  Future<Database> initInMemoryDatabase() async {
    if (kIsWeb) {
      throw UnsupportedError('In-memory database not supported on Web');
    }
    initializeDatabaseFactory();

    if (_db != null && _db!.isOpen) return _db!;

    final db = await openDatabase(
      inMemoryDatabasePath,
      version: _databaseVersion,
      onCreate: _onCreate,
      onConfigure: (db) => _onConfigure(db),
    );
    await setDatabaseForTesting(db);
    return db;
  }

  Future<Database> _initDatabase() async {
    // Initialize the correct database factory for the current platform.
    initializeDatabaseFactory();

    String path;
    if (kIsWeb) {
      // On web, use a logical database name (IndexedDB).
      path = _databaseName;
    } else {
      try {
        // On mobile/desktop, use the application documents directory.
        final documentsDirectory = await getApplicationDocumentsDirectory();
        path = p.join(documentsDirectory.path, _databaseName);
      } catch (_) {
        // Fallback for tests or environments without path_provider
        path = await getDatabasesPath();
        path = p.join(path, _databaseName);
      }
    }

    Database db;
    if (kIsWeb) {
      // On web, use databaseFactoryWeb directly.
      db = await databaseFactoryWeb.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: _databaseVersion,
          onCreate: _onCreate,
          onConfigure: _onConfigure,
          onUpgrade: _onUpgrade,
        ),
      );
    } else {
      db = await openDatabase(
        path,
        version: _databaseVersion,
        onCreate: _onCreate,
        onConfigure: (db) => _onConfigure(db),
        onUpgrade: (db, oldVersion, newVersion) => _onUpgrade(db, oldVersion, newVersion),
      );
    }

    if (!_isInitialized) {
      _isInitialized = true;
      await _migrateFromSharedPreferences(db);
    }

    return db;
  }

  Future<void> _onCreate(Database db, int version) async {
    // 1. Treatments table
    await db.execute('''
      CREATE TABLE treatments (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        dosage TEXT NOT NULL DEFAULT '',
        presentation TEXT NOT NULL DEFAULT '',
        instructions TEXT NOT NULL DEFAULT '',
        start_date TEXT NOT NULL,
        end_date TEXT,
        frequency TEXT NOT NULL,
        dose_times TEXT NOT NULL,
        stock INTEGER,
        refill_threshold INTEGER,
        is_archived INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // 2. Dose Events table
    await db.execute('''
      CREATE TABLE dose_events (
        id TEXT PRIMARY KEY,
        treatment_id TEXT NOT NULL,
        scheduled_at TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        completed_at TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (treatment_id) REFERENCES treatments(id) ON DELETE CASCADE
      )
    ''');

    // Indices for dose events for fast date and treatment lookups
    await db.execute(
      'CREATE INDEX idx_dose_events_treatment ON dose_events(treatment_id)',
    );
    await db.execute(
      'CREATE INDEX idx_dose_events_scheduled ON dose_events(scheduled_at)',
    );

    // 3. Doctors table
    await db.execute('''
      CREATE TABLE doctors (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        specialty TEXT NOT NULL DEFAULT '',
        crm TEXT NOT NULL DEFAULT '',
        crm_state TEXT NOT NULL DEFAULT '',
        phone TEXT NOT NULL DEFAULT '',
        email TEXT NOT NULL DEFAULT '',
        clinic TEXT NOT NULL DEFAULT '',
        street TEXT NOT NULL DEFAULT '',
        number TEXT NOT NULL DEFAULT '',
        complement TEXT NOT NULL DEFAULT '',
        neighborhood TEXT NOT NULL DEFAULT '',
        city TEXT NOT NULL DEFAULT '',
        state TEXT NOT NULL DEFAULT '',
        postal_code TEXT NOT NULL DEFAULT '',
        health_plans TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // 4. Consultations table
    await db.execute('''
      CREATE TABLE consultations (
        id TEXT PRIMARY KEY,
        doctor_id TEXT NOT NULL,
        date TEXT NOT NULL,
        title TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'scheduled',
        return_date TEXT,
        completed_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (doctor_id) REFERENCES doctors(id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_consultations_doctor ON consultations(doctor_id)',
    );
    await db.execute(
      'CREATE INDEX idx_consultations_date ON consultations(date)',
    );

    // 5. Health Plans table
    await db.execute('''
      CREATE TABLE health_plans (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        provider TEXT NOT NULL,
        card_number TEXT NOT NULL DEFAULT '',
        group_number TEXT NOT NULL DEFAULT '',
        beneficiary_code TEXT NOT NULL DEFAULT '',
        validity TEXT NOT NULL DEFAULT '',
        coverage_type TEXT NOT NULL DEFAULT '',
        specialties TEXT NOT NULL DEFAULT '[]',
        notes TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _onConfigure(Database db) async {
    // Enable foreign keys
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Version 2: Add completed_at column to consultations table
      await db.execute(
        'ALTER TABLE consultations ADD COLUMN completed_at TEXT',
      );
    }
    if (oldVersion < 3) {
      // Version 3: Create health_plans table for new feature
      await db.execute('''
        CREATE TABLE health_plans (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          provider TEXT NOT NULL,
          card_number TEXT NOT NULL DEFAULT '',
          group_number TEXT NOT NULL DEFAULT '',
          beneficiary_code TEXT NOT NULL DEFAULT '',
          validity TEXT NOT NULL DEFAULT '',
          coverage_type TEXT NOT NULL DEFAULT '',
          specialties TEXT NOT NULL DEFAULT '[]',
          notes TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
    }
  }

  /// Migrates existing data from SharedPreferences JSON into SQLite tables on first run.
  Future<void> _migrateFromSharedPreferences(Database db) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Check if migration was already executed
      const migrationFlagKey = 'sqlite_migration_completed_v1';
      if (prefs.getBool(migrationFlagKey) == true) {
        return;
      }

      final nowIso = DateTime.now().toUtc().toIso8601String();

      await db.transaction((txn) async {
        // 1. Migrate treatments_db
        final treatmentsJson = prefs.getString('treatments_db');
        if (treatmentsJson != null && treatmentsJson.isNotEmpty) {
          final List<dynamic> list = jsonDecode(treatmentsJson) as List<dynamic>;
          for (final item in list) {
            if (item is Map<String, dynamic>) {
              final id = item['id'] as String? ?? '';
              if (id.isEmpty) continue;

              final startDate = DateTime.parse(item['startDate'] as String).toUtc().toIso8601String();
              final endDate = item['endDate'] != null
                  ? DateTime.parse(item['endDate'] as String).toUtc().toIso8601String()
                  : null;

              await txn.insert(
                'treatments',
                {
                  'id': id,
                  'name': item['name'] as String? ?? '',
                  'dosage': item['dosage'] as String? ?? '',
                  'presentation': item['presentation'] as String? ?? '',
                  'instructions': item['instructions'] as String? ?? '',
                  'start_date': startDate,
                  'end_date': endDate,
                  'frequency': item['frequency'] as String? ?? 'daily',
                  'dose_times': jsonEncode(item['doseTimes'] ?? []),
                  'stock': item['stock'] as int?,
                  'refill_threshold': item['refillThreshold'] as int?,
                  'is_archived': (item['isArchived'] as bool? ?? false) ? 1 : 0,
                  'created_at': nowIso,
                  'updated_at': nowIso,
                },
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
          }
        }

        // 2. Migrate dose_events_db
        final doseEventsJson = prefs.getString('dose_events_db');
        if (doseEventsJson != null && doseEventsJson.isNotEmpty) {
          final List<dynamic> list = jsonDecode(doseEventsJson) as List<dynamic>;
          for (final item in list) {
            if (item is Map<String, dynamic>) {
              final id = item['id'] as String? ?? '';
              final treatmentId = item['treatmentId'] as String? ?? '';
              if (id.isEmpty || treatmentId.isEmpty) continue;

              final scheduledAt = DateTime.parse(item['scheduledAt'] as String).toUtc().toIso8601String();
              final completedAt = item['completedAt'] != null
                  ? DateTime.parse(item['completedAt'] as String).toUtc().toIso8601String()
                  : null;

              await txn.insert(
                'dose_events',
                {
                  'id': id,
                  'treatment_id': treatmentId,
                  'scheduled_at': scheduledAt,
                  'status': item['status'] as String? ?? 'pending',
                  'completed_at': completedAt,
                  'created_at': nowIso,
                },
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
          }
        }

        // 3. Migrate doctors_db
        final doctorsJson = prefs.getString('doctors_db');
        if (doctorsJson != null && doctorsJson.isNotEmpty) {
          final List<dynamic> list = jsonDecode(doctorsJson) as List<dynamic>;
          for (final item in list) {
            if (item is Map<String, dynamic>) {
              final id = item['id'] as String? ?? '';
              if (id.isEmpty) continue;

              await txn.insert(
                'doctors',
                {
                  'id': id,
                  'name': item['name'] as String? ?? '',
                  'specialty': item['specialty'] as String? ?? '',
                  'crm': item['crm'] as String? ?? '',
                  'crm_state': item['crmState'] as String? ?? '',
                  'phone': item['phone'] as String? ?? '',
                  'email': item['email'] as String? ?? '',
                  'clinic': item['clinic'] as String? ?? '',
                  'street': item['street'] as String? ?? '',
                  'number': item['number'] as String? ?? '',
                  'complement': item['complement'] as String? ?? '',
                  'neighborhood': item['neighborhood'] as String? ?? '',
                  'city': item['city'] as String? ?? '',
                  'state': item['state'] as String? ?? '',
                  'postal_code': item['postalCode'] as String? ?? '',
                  'health_plans': item['healthPlans'] as String? ?? '',
                  'notes': item['notes'] as String? ?? '',
                  'created_at': nowIso,
                  'updated_at': nowIso,
                },
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
          }
        }

        // 4. Migrate consultations_db
        final consultationsJson = prefs.getString('consultations_db');
        if (consultationsJson != null && consultationsJson.isNotEmpty) {
          final List<dynamic> list = jsonDecode(consultationsJson) as List<dynamic>;
          for (final item in list) {
            if (item is Map<String, dynamic>) {
              final id = item['id'] as String? ?? '';
              final doctorId = item['doctorId'] as String? ?? '';
              if (id.isEmpty || doctorId.isEmpty) continue;

              final date = DateTime.parse(item['date'] as String).toUtc().toIso8601String();
              final returnDate = item['returnDate'] != null
                  ? DateTime.parse(item['returnDate'] as String).toUtc().toIso8601String()
                  : null;

              await txn.insert(
                'consultations',
                {
                  'id': id,
                  'doctor_id': doctorId,
                  'date': date,
                  'title': item['title'] as String? ?? '',
                  'notes': item['notes'] as String? ?? '',
                  'status': item['status'] as String? ?? 'scheduled',
                  'return_date': returnDate,
                  'created_at': nowIso,
                  'updated_at': nowIso,
                },
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
          }
        }
      });

      // Mark migration as completed so it does not repeat
      await prefs.setBool(migrationFlagKey, true);
    } catch (e) {
      debugPrint('Database migration warning: $e');
    }
  }

  /// Closes database connection.
  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }
}
