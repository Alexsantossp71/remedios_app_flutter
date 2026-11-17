import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// Import the correct database factory based on platform.
// On web: uses sqflite_common_ffi_web (IndexedDB + WASM).
// On mobile/desktop: uses sqflite's default implementation.
import 'database_factory_web.dart' if (dart.library.io) 'database_factory_io.dart';

/// Database service for managing SQLite database instance, schemas, and migrations.
class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  // Fresh database namespace: the previous v11 database remains untouched
  // and can be recovered by restoring the previous database name.
  static const String _databaseName = 'remedios_app_fresh_v1.db';
  static const int _databaseVersion = 11;

  Database? _db;

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
  }

  /// Executa as migrações reais num banco aberto em versão anterior —
  /// teste da trilha v10 → v11 sem duplicar o SQL do [_onUpgrade].
  @visibleForTesting
  Future<void> applyUpgradesForTesting(Database db, int oldVersion) {
    return _onUpgrade(db, oldVersion, _databaseVersion);
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

    // Intentionally do not import legacy SharedPreferences data. This fresh
    // database starts empty; the previous SQLite file and legacy preference
    // values are left untouched for manual recovery if needed.
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
        weekdays TEXT,
        stock INTEGER,
        refill_threshold INTEGER,
        is_archived INTEGER NOT NULL DEFAULT 0,
        prescriber_doctor_id TEXT,
        prescriber_name TEXT,
        prescriber_crm TEXT,
        prescriber_crm_state TEXT,
        prescribed_on TEXT,
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

    // 6. User Profile table (linha única: perfil do usuário)
    await db.execute('''
      CREATE TABLE user_profile (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        nome TEXT NOT NULL DEFAULT '',
        cpf TEXT,
        data_nascimento TEXT,
        foto_path TEXT,
        tipo_sanguineo TEXT,
        alergias TEXT NOT NULL DEFAULT '[]',
        condicoes_cronicas TEXT NOT NULL DEFAULT '[]',
        peso REAL,
        altura REAL,
        telefone TEXT,
        observacoes TEXT,
        consent_at TEXT,
        ai_consent_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // 7. Emergency Contacts table (N contatos)
    await db.execute('''
      CREATE TABLE emergency_contacts (
        id TEXT PRIMARY KEY,
        nome TEXT NOT NULL,
        parentesco TEXT NOT NULL DEFAULT '',
        telefone TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // 8. Exams table (pedidos/agendamentos/laudos de exames)
    await db.execute('''
      CREATE TABLE exams (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'requested',
        date TEXT NOT NULL,
        time TEXT,
        photo TEXT,
        doctor_id TEXT NOT NULL DEFAULT '',
        doctor_name TEXT NOT NULL DEFAULT '',
        place TEXT NOT NULL DEFAULT '',
        results TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // 9. Treatment prescriptions table (histórico de "quem receitou e em
    // que dia" — um registro por renovação de receita, nunca sobrescrito)
    await db.execute('''
      CREATE TABLE treatment_prescriptions (
        id TEXT PRIMARY KEY,
        treatment_id TEXT NOT NULL,
        doctor_id TEXT,
        doctor_name TEXT NOT NULL,
        doctor_crm TEXT,
        doctor_crm_state TEXT,
        prescribed_on TEXT NOT NULL,
        source TEXT NOT NULL DEFAULT 'manual',
        created_at TEXT NOT NULL,
        FOREIGN KEY (treatment_id) REFERENCES treatments(id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_treatment_prescriptions_treatment '
      'ON treatment_prescriptions(treatment_id)',
    );

    // 10. Lab results table (laudos de laboratório com valores por marcador)
    await db.execute('''
      CREATE TABLE lab_results (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        lab_name TEXT NOT NULL DEFAULT '',
        photo TEXT,
        values_json TEXT NOT NULL DEFAULT '[]',
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
    if (oldVersion < 4) {
      // Version 4: Create user_profile and emergency_contacts tables
      await db.execute('''
        CREATE TABLE user_profile (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          nome TEXT NOT NULL DEFAULT '',
          data_nascimento TEXT,
          foto_path TEXT,
          tipo_sanguineo TEXT,
          alergias TEXT NOT NULL DEFAULT '[]',
          condicoes_cronicas TEXT NOT NULL DEFAULT '[]',
          peso REAL,
          altura REAL,
          telefone TEXT,
          observacoes TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE emergency_contacts (
          id TEXT PRIMARY KEY,
          nome TEXT NOT NULL,
          parentesco TEXT NOT NULL DEFAULT '',
          telefone TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 5) {
      // Version 5: Add CPF column to user_profile
      await db.execute('ALTER TABLE user_profile ADD COLUMN cpf TEXT');
    }
    if (oldVersion < 6) {
      // Version 6: Add consent_at column (LGPD consent timestamp)
      await db.execute('ALTER TABLE user_profile ADD COLUMN consent_at TEXT');
    }
    if (oldVersion < 7) {
      // Version 7: Add weekdays column (frequency weekly — "N vezes por semana",
      // ex.: metotrexato 1x/sem). NULL = frequência não semanal.
      await db.execute('ALTER TABLE treatments ADD COLUMN weekdays TEXT');
    }
    if (oldVersion < 8) {
      // Version 8: Add ai_consent_at column (consentimento para envio de
      // dados clínicos ao serviço de IA; timestamp UTC, NULL = não autorizou).
      await db.execute('ALTER TABLE user_profile ADD COLUMN ai_consent_at TEXT');
    }
    if (oldVersion < 9) {
      // Version 9: Create exams table (módulo de exames — pedido → agendado
      // → realizado, com foto opcional do pedido/laudo em base64).
      await db.execute('''
        CREATE TABLE exams (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          category TEXT NOT NULL DEFAULT '',
          status TEXT NOT NULL DEFAULT 'requested',
          date TEXT NOT NULL,
          time TEXT,
          photo TEXT,
          doctor_id TEXT NOT NULL DEFAULT '',
          doctor_name TEXT NOT NULL DEFAULT '',
          place TEXT NOT NULL DEFAULT '',
          results TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 10) {
      // Version 10: Create lab_results table (laudos com valores por
      // marcador; a lista vive em values_json e as flags são recalculadas
      // no app ao ler — a IA nunca classifica resultado).
      await db.execute('''
        CREATE TABLE lab_results (
          id TEXT PRIMARY KEY,
          date TEXT NOT NULL,
          lab_name TEXT NOT NULL DEFAULT '',
          photo TEXT,
          values_json TEXT NOT NULL DEFAULT '[]',
          notes TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 11) {
      // Version 11: quem receitou — snapshot no tratamento (médico, CRM e
      // data da receita para o card/formulário) + histórico completo em
      // treatment_prescriptions (um registro por renovação, nunca sobrescrito).
      await db.execute(
        'ALTER TABLE treatments ADD COLUMN prescriber_doctor_id TEXT',
      );
      await db.execute(
        'ALTER TABLE treatments ADD COLUMN prescriber_name TEXT',
      );
      await db.execute('ALTER TABLE treatments ADD COLUMN prescriber_crm TEXT');
      await db.execute(
        'ALTER TABLE treatments ADD COLUMN prescriber_crm_state TEXT',
      );
      await db.execute('ALTER TABLE treatments ADD COLUMN prescribed_on TEXT');
      await db.execute('''
        CREATE TABLE treatment_prescriptions (
          id TEXT PRIMARY KEY,
          treatment_id TEXT NOT NULL,
          doctor_id TEXT,
          doctor_name TEXT NOT NULL,
          doctor_crm TEXT,
          doctor_crm_state TEXT,
          prescribed_on TEXT NOT NULL,
          source TEXT NOT NULL DEFAULT 'manual',
          created_at TEXT NOT NULL,
          FOREIGN KEY (treatment_id) REFERENCES treatments(id) ON DELETE CASCADE
        )
      ''');
      await db.execute(
        'CREATE INDEX idx_treatment_prescriptions_treatment '
        'ON treatment_prescriptions(treatment_id)',
      );
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
