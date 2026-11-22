import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// Import the correct database factory based on platform.
// On web: uses sqflite_common_ffi_web with the SQLite3MC worker.
// On Android/desktop: uses sqflite_common_ffi with the SQLite3MC build.
import 'database_factory_web.dart'
    if (dart.library.io) 'database_factory_io.dart';

import 'database_encryption/database_encryption_service.dart';
import 'database_encryption/database_encryption_service_web.dart'
    if (dart.library.io) 'database_encryption/database_encryption_service_io.dart';
import 'database_encryption/encrypted_database_opener_stub.dart'
    if (dart.library.io) 'database_encryption/encrypted_database_opener.dart';
import 'database_key/database_key_service.dart';
import 'demo_data_seeder.dart';

/// Database service for managing SQLite database instance, schemas, and migrations.
class DatabaseService {
  /// Test-only override of the encryption orchestration. When set, `_initDatabase`
  /// uses it instead of the platform default, enabling end-to-end tests with
  /// injected key stores and directories.
  @visibleForTesting
  static DatabaseEncryptionService? encryptionServiceOverride;

  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  // Keep the established database name so existing v11 data remains visible.
  // The ACTIVE database for Android/Web is the encrypted database created
  // next to it (see DatabaseEncryptionService); the legacy file is preserved
  // untouched as the pre-migration original.
  static const String _databaseName = 'remedios_app.db';
  static const int _databaseVersion = 11;

  Database? _db;

  /// Failure of the last [database] open attempt, exposed for the unlock/
  /// recovery UI. Null when the database opened successfully.
  Object? lastOpenError;

  /// Quando true, [database] abre um banco em memória (não persistido,
  /// sem criptografia) com dados mock para o visitante explorar a UI.
  /// Ativado pelo CTA "Ver demo" da WelcomeScreen. Desativado por
  /// `disableDemoMode()` quando o usuário sai do demo.
  static bool demoMode = false;

  /// Ativa o modo demo: banco em memória + dados mock, sem cofre.
  static void enableDemoMode() => demoMode = true;

  /// Desativa o modo demo e fecha o banco em memória. Próxima chamada
  /// a [database] abre o fluxo normal (criptografia + cofre).
  static void disableDemoMode() => demoMode = false;

  /// Returns the singleton [Database] instance.
  Future<Database> get database async {
    if (demoMode) {
      return _initDemoDatabase();
    }
    if (_db != null && _db!.isOpen) return _db!;
    try {
      _db = await _initDatabase();
      lastOpenError = null;
      return _db!;
    } catch (error) {
      lastOpenError = error;
      rethrow;
    }
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

  /// Cria o schema completo v11 com o mesmo SQL de produção — usado pelos
  /// testes de migração para construir bancos legados realistas.
  @visibleForTesting
  Future<void> createSchemaForTesting(Database db) {
    return _onCreate(db, _databaseVersion);
  }

  /// Initialize an in-memory database for testing.
  @visibleForTesting
  Future<Database> initInMemoryDatabase() async {
    if (kIsWeb) {
      throw UnsupportedError('In-memory database not supported on Web');
    }
    // Tests need a working FFI factory on every desktop platform CI runs on
    // (macOS included — the production gate skips it). Use the test-only
    // initializer instead of the platform-gated production one.
    initializeDatabaseFactoryForTesting();

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

  /// Inicializa o banco em memória para o modo demo.
  ///
  /// Funciona em Web e native: usa a factory da plataforma (databaseFactoryWeb
  /// em Web com SQLite3MC WASM SharedWorker, sqflite_common_ffi em native).
  /// O banco vive em memória apenas — fechando a aba ou saindo do demo perde
  /// tudo. Sem criptografia, sem cofre, sem persistência.
  ///
  /// Após criar o schema v11, chama [DemoDataSeeder.seed] para popular com
  /// dados mock (2 treatments, 1 doctor, 1 consultation, 1 exam, 1 lab result,
  /// user profile, emergency contacts, doses de hoje).
  Future<Database> _initDemoDatabase() async {
    initializeDatabaseFactory();
    if (_db != null && _db!.isOpen) return _db!;

    if (kIsWeb) {
      // Web: usa factory com inMemory: true — dados vivem só na memória
      // do SharedWorker, sem OPFS, sem persistência. Fecha a aba = perde tudo.
      final db = await databaseFactoryWebDemo.openDatabase(
        'demo.db',
        options: OpenDatabaseOptions(
          version: _databaseVersion,
          onCreate: _onCreate,
          onConfigure: (db) => _onConfigure(db),
        ),
      );
      _db = db;
      await DemoDataSeeder.seed(db);
      return db;
    }

    // Native: in-memory path direto (sqflite_common_ffi suporta :memory:).
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: _databaseVersion,
      onCreate: _onCreate,
      onConfigure: (db) => _onConfigure(db),
    );
    _db = db;
    // Popula com dados mock para o visitante explorar a UI.
    await DemoDataSeeder.seed(db);
    return db;
  }

  Future<Database> _initDatabase() async {
    // Initialize the correct database factory for the current platform.
    initializeDatabaseFactory();

    // Encrypted path (Android + Web, the scope of this delivery):
    // 1. resolve the key BEFORE any file operation;
    // 2. run the legacy → encrypted migration when needed (backup, copy,
    //    validate, atomic swap — the original file is never modified);
    // 3. open the encrypted database with the key PRAGMAs applied and
    //    validated in onConfigure, BEFORE any schema read.
    // Out-of-scope native platforms (iOS/macOS) keep the legacy plaintext
    // behavior below, unchanged.
    final service =
        encryptionServiceOverride ??
        createDatabaseEncryptionService(DatabaseKeyService.instance);
    final plan = await service.prepare();
    if (plan != null) {
      lastOpenError = null;
      return _openEncryptedDatabase(plan);
    }

    return _openLegacyPlaintextDatabase();
  }

  Future<Database> _openEncryptedDatabase(EncryptionOpenPlan plan) async {
    if (kIsWeb) {
      return databaseFactoryWeb.openDatabase(
        plan.databaseName,
        options: OpenDatabaseOptions(
          version: _databaseVersion,
          onCreate: _onCreate,
          onConfigure: (db) async {
            applyEncryptionPragmas(db, plan.key);
            await validateEncryptedKeyOrThrow(db);
            await _onConfigure(db);
          },
          onUpgrade: _onUpgrade,
        ),
      );
    }
    // Android/desktop through the FFI factory backed by sqlite3mc.
    return openEncryptedSqfliteDatabase(
      plan.databaseName,
      key: plan.key,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: (db, oldVersion, newVersion) =>
          _onUpgrade(db, oldVersion, newVersion),
      extraOnConfigure: _onConfigure,
    );
  }

  /// Legacy plaintext open path (iOS/macOS, out of the encryption scope).
  Future<Database> _openLegacyPlaintextDatabase() async {
    String path;
    if (kIsWeb) {
      path = _databaseName;
    } else {
      try {
        final documentsDirectory = await getApplicationDocumentsDirectory();
        path = p.join(documentsDirectory.path, _databaseName);
      } catch (_) {
        path = await getDatabasesPath();
        path = p.join(path, _databaseName);
      }
    }

    if (kIsWeb) {
      return databaseFactoryWeb.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: _databaseVersion,
          onCreate: _onCreate,
          onConfigure: _onConfigure,
          onUpgrade: _onUpgrade,
        ),
      );
    }
    return openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onConfigure: (db) => _onConfigure(db),
      onUpgrade: (db, oldVersion, newVersion) =>
          _onUpgrade(db, oldVersion, newVersion),
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // 1. Treatments table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS treatments (
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
      CREATE TABLE IF NOT EXISTS dose_events (
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
      'CREATE INDEX IF NOT EXISTS idx_dose_events_treatment ON dose_events(treatment_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_dose_events_scheduled ON dose_events(scheduled_at)',
    );

    // 3. Doctors table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS doctors (
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
      CREATE TABLE IF NOT EXISTS consultations (
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
      'CREATE INDEX IF NOT EXISTS idx_consultations_doctor ON consultations(doctor_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_consultations_date ON consultations(date)',
    );

    // 5. Health Plans table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS health_plans (
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
      CREATE TABLE IF NOT EXISTS user_profile (
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
      CREATE TABLE IF NOT EXISTS emergency_contacts (
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
      CREATE TABLE IF NOT EXISTS exams (
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
      CREATE TABLE IF NOT EXISTS treatment_prescriptions (
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
      'CREATE INDEX IF NOT EXISTS idx_treatment_prescriptions_treatment '
      'ON treatment_prescriptions(treatment_id)',
    );

    // 10. Lab results table (laudos de laboratório com valores por marcador)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS lab_results (
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
        CREATE TABLE IF NOT EXISTS health_plans (
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
        CREATE TABLE IF NOT EXISTS user_profile (
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
        CREATE TABLE IF NOT EXISTS emergency_contacts (
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
      await db.execute(
        'ALTER TABLE user_profile ADD COLUMN ai_consent_at TEXT',
      );
    }
    if (oldVersion < 9) {
      // Version 9: Create exams table (módulo de exames — pedido → agendado
      // → realizado, com foto opcional do pedido/laudo em base64).
      await db.execute('''
        CREATE TABLE IF NOT EXISTS exams (
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
        CREATE TABLE IF NOT EXISTS lab_results (
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
        CREATE TABLE IF NOT EXISTS treatment_prescriptions (
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
        'CREATE INDEX IF NOT EXISTS idx_treatment_prescriptions_treatment '
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
