import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common/sqlite_api.dart' as sqflite;
import 'package:remedios_app_flutter/services/database_encryption/database_encryption_service_io.dart';
import 'package:remedios_app_flutter/services/database_key/database_key_service.dart';
import 'package:remedios_app_flutter/services/database_key/database_key_store.dart';
import 'package:remedios_app_flutter/services/database_key/in_memory_database_key_store.dart';
import 'package:remedios_app_flutter/services/database_encryption/database_migration_io.dart';
import 'package:remedios_app_flutter/services/database_encryption/database_preservation.dart';
import 'package:remedios_app_flutter/services/database_encryption/encrypted_database_opener.dart';
import 'package:remedios_app_flutter/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/sqlite3.dart' as sql3;

/// Generates a random 256-bit key in hex (test keys only).
List<int> newKey() {
  final random = Random.secure();
  return List<int>.generate(32, (_) => random.nextInt(256));
}

const legacyName = 'remedios_app.db';
const encryptedName = 'remedios_app_enc.db';

/// Seeds a realistic v11 dataset exercising every table.
Future<void> _seedV11Data(Database db) async {
  final now = DateTime.now().toUtc().toIso8601String();

  await db.insert('treatments', {
    'id': 'trt-1',
    'name': 'Losartana 50mg',
    'dosage': '1 comprimido',
    'presentation': 'Caixa 30 comprimidos',
    'instructions': 'Pela manhã',
    'start_date': '2026-01-10',
    'frequency': 'daily',
    'dose_times': '["08:00"]',
    'stock': 28,
    'refill_threshold': 5,
    'is_archived': 0,
    'prescriber_doctor_id': 'doc-1',
    'prescriber_name': 'Dra. Ana',
    'prescriber_crm': '12345',
    'prescriber_crm_state': 'SP',
    'prescribed_on': '2026-01-08',
    'created_at': now,
    'updated_at': now,
  });
  await db.insert('treatments', {
    'id': 'trt-2',
    'name': 'Metformina 850mg',
    'dosage': '1 comprimido',
    'presentation': '',
    'instructions': 'Após almoço',
    'start_date': '2026-02-01',
    'frequency': 'daily',
    'dose_times': '["12:30","19:00"]',
    'weekdays': null,
    'is_archived': 0,
    'created_at': now,
    'updated_at': now,
  });
  await db.insert('dose_events', {
    'id': 'dose-1',
    'treatment_id': 'trt-1',
    'scheduled_at': '2026-03-01T08:00:00.000Z',
    'status': 'taken',
    'completed_at': '2026-03-01T08:05:00.000Z',
    'created_at': now,
  });
  await db.insert('dose_events', {
    'id': 'dose-2',
    'treatment_id': 'trt-1',
    'scheduled_at': '2026-03-01T20:00:00.000Z',
    'status': 'pending',
    'created_at': now,
  });
  await db.insert('doctors', {
    'id': 'doc-1',
    'name': 'Dra. Ana Souza',
    'specialty': 'Cardiologia',
    'crm': '12345',
    'crm_state': 'SP',
    'created_at': now,
    'updated_at': now,
  });
  await db.insert('consultations', {
    'id': 'con-1',
    'doctor_id': 'doc-1',
    'date': '2026-03-15',
    'title': 'Consulta de rotina',
    'status': 'scheduled',
    'created_at': now,
    'updated_at': now,
  });
  await db.insert('health_plans', {
    'id': 'hp-1',
    'name': 'Plano Saúde Plus',
    'provider': 'Operadora X',
    'card_number': '000-111-222',
    'created_at': now,
    'updated_at': now,
  });
  await db.insert('user_profile', {
    'id': 1,
    'nome': 'Paciente Teste',
    'cpf': '123.456.789-00',
    'tipo_sanguineo': 'O+',
    'alergias': '["dipirona"]',
    'condicoes_cronicas': '["hipertensão"]',
    'created_at': now,
    'updated_at': now,
  });
  await db.insert('emergency_contacts', {
    'id': 'ec-1',
    'nome': 'Maria (esposa)',
    'parentesco': 'cônjuge',
    'telefone': '+55 11 99999-0000',
    'created_at': now,
    'updated_at': now,
  });
  await db.insert('exams', {
    'id': 'ex-1',
    'name': 'Hemograma completo',
    'category': 'laboratório',
    'status': 'requested',
    'date': '2026-03-20',
    'created_at': now,
    'updated_at': now,
  });
  await db.insert('treatment_prescriptions', {
    'id': 'rx-1',
    'treatment_id': 'trt-1',
    'doctor_id': 'doc-1',
    'doctor_name': 'Dra. Ana Souza',
    'doctor_crm': '12345',
    'doctor_crm_state': 'SP',
    'prescribed_on': '2026-01-08',
    'source': 'manual',
    'created_at': now,
  });
  await db.insert('lab_results', {
    'id': 'lab-1',
    'date': '2026-03-22',
    'lab_name': 'Laboratório Central',
    'values_json': '[{"marker":"hemoglobina","value":"13.5"}]',
    'created_at': now,
    'updated_at': now,
  });
}

Future<sqflite.Database> _createV11LegacyDb(String path) async {
  final service = DatabaseService.instance;
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 11,
      onCreate: (db, version) => service.createSchemaForTesting(db),
    ),
  );
  await _seedV11Data(db);
  return db;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // The code under test (DatabaseService._openLegacyPlaintextDatabase)
    // uses the GLOBAL sqflite factory via getDatabasesPath()/openDatabase().
    // On macOS the production gate skips FFI init, so set the global factory
    // here to keep the end-to-end migration tests green on every desktop CI
    // lane (P3-1). Seeding already uses databaseFactoryFfi explicitly.
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('rnh-enc-test-');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('DatabaseMigrationIo — banco novo e banco v11 populado', () {
    test(
      'banco novo: nada a migrar (retorna null, não cria arquivos)',
      () async {
        final migration = DatabaseMigrationIo();
        final result = await migration.migrateIfNeeded(
          legacyPath: '${tempDir.path}/$legacyName',
          encryptedPath: '${tempDir.path}/$encryptedName',
          key: newKey(),
        );
        expect(result, isNull);
        expect(File('${tempDir.path}/$encryptedName').existsSync(), isFalse);
        expect(File('${tempDir.path}/$legacyName').existsSync(), isFalse);
      },
    );

    test(
      'v11 populado: migra, preserva registros/IDs/relacionamentos e mantém original',
      () async {
        final legacyPath = '${tempDir.path}/$legacyName';
        final encryptedPath = '${tempDir.path}/$encryptedName';
        final key = newKey();

        final legacyDb = await _createV11LegacyDb(legacyPath);
        await legacyDb.close();

        final legacyBytes = File(legacyPath).readAsBytesSync();

        final migration = DatabaseMigrationIo();
        final result = await migration.migrateIfNeeded(
          legacyPath: legacyPath,
          encryptedPath: encryptedPath,
          key: key,
        );

        expect(result, isNotNull);
        expect(result!.legacyVersion, 11);
        expect(result.preservationProblems, isEmpty);
        expect(result.tablesBefore['treatments']!.count, 2);
        expect(result.tablesAfter['treatments']!.ids, contains('trt-1'));

        // O arquivo original permanece intacto (bytes idênticos).
        expect(File(legacyPath).readAsBytesSync(), legacyBytes);
        // ... e continua sendo um SQLite em texto claro.
        expect(
          detectSqliteFileFormat(legacyPath),
          DatabaseFileFormat.plaintextSqlite,
        );
        // O arquivo criptografado existe e NÃO tem header plaintext.
        expect(
          detectSqliteFileFormat(encryptedPath),
          DatabaseFileFormat.encryptedOrUnknown,
        );
        // O backup verificado foi criado.
        expect(Directory(result.backupPath).parent.existsSync(), isTrue);
        expect(File(result.backupPath).existsSync(), isTrue);

        // Reabrir criptografado e validar todos os dados.
        final reopened = await openEncryptedSqfliteDatabase(
          encryptedPath,
          key: key,
          version: 11,
          onCreate: (db, version) async {},
          onUpgrade: (db, o, n) async {},
        );
        final treatments = await reopened.query('treatments');
        expect(treatments.length, 2);
        final losartana = treatments.firstWhere((row) => row['id'] == 'trt-1');
        expect(losartana['name'], 'Losartana 50mg');
        expect(losartana['prescriber_name'], 'Dra. Ana');

        final doses = await reopened.query('dose_events');
        expect(doses.length, 2);
        // Relacionamento preservado: dose-1 → trt-1.
        expect(doses.first['treatment_id'], 'trt-1');

        final profile = await reopened.query('user_profile');
        expect(profile.single['nome'], 'Paciente Teste');
        expect(profile.single['cpf'], '123.456.789-00');

        for (final table in databaseV11Tables) {
          final rows = await reopened.query('"$table"');
          expect(rows, isNotEmpty, reason: '$table deveria ter registros');
        }
        await reopened.close();

        // Migração repetida: nada a fazer.
        final second = await migration.migrateIfNeeded(
          legacyPath: legacyPath,
          encryptedPath: encryptedPath,
          key: key,
        );
        expect(second, isNull);
      },
    );

    test('v10 populado: migra e depois aplica o upgrade v10 → v11', () async {
      final legacyPath = '${tempDir.path}/$legacyName';
      final encryptedPath = '${tempDir.path}/$encryptedName';
      final key = newKey();
      final service = DatabaseService.instance;

      // Banco legado em v10: schema completo + downgrade dos elementos v11.
      final legacyDb = await databaseFactoryFfi.openDatabase(
        legacyPath,
        options: OpenDatabaseOptions(
          version: 10,
          onCreate: (db, version) => service.createSchemaForTesting(db),
        ),
      );
      await legacyDb.execute('DROP TABLE treatment_prescriptions');
      for (final column in [
        'prescriber_doctor_id',
        'prescriber_name',
        'prescriber_crm',
        'prescriber_crm_state',
        'prescribed_on',
      ]) {
        await legacyDb.execute('ALTER TABLE treatments DROP COLUMN $column');
      }
      final now = DateTime.now().toUtc().toIso8601String();
      await legacyDb.insert('treatments', {
        'id': 'trt-antigo',
        'name': 'AAS 100mg',
        'dosage': '1 comprimido',
        'presentation': '',
        'instructions': '',
        'start_date': '2025-06-01',
        'frequency': 'daily',
        'dose_times': '["07:00"]',
        'is_archived': 0,
        'created_at': now,
        'updated_at': now,
      });
      await legacyDb.close();

      final migration = DatabaseMigrationIo();
      final result = await migration.migrateIfNeeded(
        legacyPath: legacyPath,
        encryptedPath: encryptedPath,
        key: key,
      );
      expect(result!.legacyVersion, 10);

      // Reabertura em v11 pelo fluxo real do DatabaseService: o onUpgrade
      // existente da aplicação deve rodar sobre o banco criptografado.
      final opened = await openEncryptedSqfliteDatabase(
        encryptedPath,
        key: key,
        version: 11,
        onCreate: (db, version) async {},
        onUpgrade: (db, oldVersion, newVersion) =>
            service.applyUpgradesForTesting(db, oldVersion),
      );
      final columns = await opened.rawQuery('PRAGMA table_info(treatments)');
      final names = columns.map((c) => c['name']).toSet();
      expect(names, containsAll(['prescriber_name', 'prescriber_crm']));
      final rows = await opened.query('treatments');
      expect(rows.single['name'], 'AAS 100mg');
      expect(rows.single['id'], 'trt-antigo');
      await opened.close();
    });
  });

  group('DatabaseMigrationIo — falha segura', () {
    test('chave errada ao reabrir: erro, sem recriar banco vazio', () async {
      final legacyPath = '${tempDir.path}/$legacyName';
      final encryptedPath = '${tempDir.path}/$encryptedName';

      final legacyDb = await _createV11LegacyDb(legacyPath);
      await legacyDb.close();

      final key = newKey();
      await DatabaseMigrationIo().migrateIfNeeded(
        legacyPath: legacyPath,
        encryptedPath: encryptedPath,
        key: key,
      );

      final encryptedBytes = File(encryptedPath).readAsBytesSync();

      // Reabrir com chave diferente deve falhar na validação do schema.
      await expectLater(
        openEncryptedSqfliteDatabase(
          encryptedPath,
          key: newKey(),
          version: 11,
          onCreate: (db, version) async {},
          onUpgrade: (db, o, n) async {},
        ),
        throwsA(anything),
      );

      // O banco criptografado permanece intacto (não foi recriado vazio).
      expect(File(encryptedPath).readAsBytesSync(), encryptedBytes);
    });

    test('legado corrompido: migração aborta sem alterar nada', () async {
      final legacyPath = '${tempDir.path}/$legacyName';
      final encryptedPath = '${tempDir.path}/$encryptedName';
      final garbage = List<int>.generate(4096, (i) => i % 251);
      File(legacyPath).writeAsBytesSync(garbage);

      await expectLater(
        DatabaseMigrationIo().migrateIfNeeded(
          legacyPath: legacyPath,
          encryptedPath: encryptedPath,
          key: newKey(),
        ),
        throwsA(isA<DatabaseMigrationFailedException>()),
      );
      expect(File(legacyPath).readAsBytesSync(), garbage);
      expect(File(encryptedPath).existsSync(), isFalse);
    });

    test(
      'interrupção durante a cópia: original intacto e retomada limpa',
      () async {
        final legacyPath = '${tempDir.path}/$legacyName';
        final encryptedPath = '${tempDir.path}/$encryptedName';
        final key = newKey();

        final legacyDb = await _createV11LegacyDb(legacyPath);
        await legacyDb.close();
        final legacyBytes = File(legacyPath).readAsBytesSync();

        // Interrompe no meio da migração (falha injetada após a cópia).
        final failing = DatabaseMigrationIo()..failAfterCopyForTesting = true;
        await expectLater(
          failing.migrateIfNeeded(
            legacyPath: legacyPath,
            encryptedPath: encryptedPath,
            key: key,
          ),
          throwsA(isA<DatabaseMigrationFailedException>()),
        );

        // Estado pós-interrupção: original intacto, sem banco de destino.
        expect(File(legacyPath).readAsBytesSync(), legacyBytes);
        expect(File(encryptedPath).existsSync(), isFalse);

        // Retomada na próxima inicialização: migração completa com sucesso.
        final resumed = await DatabaseMigrationIo().migrateIfNeeded(
          legacyPath: legacyPath,
          encryptedPath: encryptedPath,
          key: key,
        );
        expect(resumed, isNotNull);
        expect(resumed!.preservationProblems, isEmpty);
        expect(resumed.tablesAfter['treatments']!.count, 2);
      },
    );

    test(
      'arquivo temporário órfão de execução interrompida é descartado',
      () async {
        final legacyPath = '${tempDir.path}/$legacyName';
        final encryptedPath = '${tempDir.path}/$encryptedName';
        final key = newKey();

        final legacyDb = await _createV11LegacyDb(legacyPath);
        await legacyDb.close();
        File(
          '$encryptedPath.migrating.tmp',
        ).writeAsBytesSync(List.filled(128, 9));

        final result = await DatabaseMigrationIo().migrateIfNeeded(
          legacyPath: legacyPath,
          encryptedPath: encryptedPath,
          key: key,
        );
        expect(result, isNotNull);
        expect(File('$encryptedPath.migrating.tmp').existsSync(), isFalse);
      },
    );

    test(
      'concorrência: duas migrações simultâneas não corrompem nada',
      () async {
        final legacyPath = '${tempDir.path}/$legacyName';
        final encryptedPath = '${tempDir.path}/$encryptedName';
        final key = newKey();

        final legacyDb = await _createV11LegacyDb(legacyPath);
        await legacyDb.close();
        final legacyBytes = File(legacyPath).readAsBytesSync();

        final results = await Future.wait([
          DatabaseMigrationIo().migrateIfNeeded(
            legacyPath: legacyPath,
            encryptedPath: encryptedPath,
            key: key,
          ),
          DatabaseMigrationIo().migrateIfNeeded(
            legacyPath: legacyPath,
            encryptedPath: encryptedPath,
            key: key,
          ),
        ]);

        final migrated = results.whereType<DatabaseMigrationResult>().toList();
        expect(
          migrated.length,
          1,
          reason: 'exatamente uma migração deve executar',
        );
        expect(File(legacyPath).readAsBytesSync(), legacyBytes);
        expect(
          detectSqliteFileFormat(encryptedPath),
          DatabaseFileFormat.encryptedOrUnknown,
        );
      },
    );

    test('WAL/journal legado entram no backup', () async {
      final legacyPath = '${tempDir.path}/$legacyName';
      final encryptedPath = '${tempDir.path}/$encryptedName';
      final key = newKey();
      final legacyDb = await _createV11LegacyDb(legacyPath);
      await legacyDb.close();
      File('$legacyPath-wal').writeAsBytesSync(List.filled(32, 1));

      final result = await DatabaseMigrationIo().migrateIfNeeded(
        legacyPath: legacyPath,
        encryptedPath: encryptedPath,
        key: key,
      );
      expect(result, isNotNull);
      expect(File('${result!.backupPath}-wal').existsSync(), isTrue);
    });
  });

  group('Detecção de formato', () {
    test('arquivo ausente → notFound', () {
      expect(
        detectSqliteFileFormat('${tempDir.path}/nao-existe.db'),
        DatabaseFileFormat.notFound,
      );
    });

    test('plaintext tem o header mágico; cifrado não', () async {
      final plaintextPath = '${tempDir.path}/plain.db';
      final db = sql3.sqlite3.open(plaintextPath);
      db.execute('CREATE TABLE t (v TEXT)');
      db.close();
      expect(
        detectSqliteFileFormat(plaintextPath),
        DatabaseFileFormat.plaintextSqlite,
      );

      final encryptedPath = '${tempDir.path}/enc.db';
      final key = newKey();
      final encDb = sql3.sqlite3.open(encryptedPath);
      applyEncryptionPragmas(encDb, key);
      encDb.execute('CREATE TABLE t (v TEXT)');
      encDb.close();
      expect(
        detectSqliteFileFormat(encryptedPath),
        DatabaseFileFormat.encryptedOrUnknown,
      );
    });
  });

  group('Cofre de chaves ausente nunca cria banco vazio', () {
    test('key incompleta: prepare() lança e não toca nos arquivos', () async {
      final legacyPath = '${tempDir.path}/$legacyName';
      final legacyDb = await _createV11LegacyDb(legacyPath);
      await legacyDb.close();
      final legacyBytes = File(legacyPath).readAsBytesSync();

      DatabaseKeyService.resetInstanceForTesting(store: _BrokenKeyStore());
      final keyService = DatabaseKeyService.instance;
      final service = DatabaseEncryptionServiceIo(
        keyService: keyService,
        directoryResolver: () async => tempDir.path,
      );

      await expectLater(
        service.prepare(),
        throwsA(isA<DatabaseKeyRecoveryRequiredException>()),
      );

      // Nenhum arquivo novo foi criado e o original segue intacto.
      expect(File('${tempDir.path}/$encryptedName').existsSync(), isFalse);
      expect(
        File('${tempDir.path}/$legacyName').readAsBytesSync(),
        legacyBytes,
      );
      expect(
        Directory(
          '${tempDir.path}/remedios_app_backup_pre_encryption',
        ).existsSync(),
        isFalse,
      );
    });

    test(
      'key ausente em banco novo: prepare() cria chave e plano fresh',
      () async {
        DatabaseKeyService.resetInstanceForTesting(
          store: InMemoryDatabaseKeyStore(),
        );
        final keyService = DatabaseKeyService.instance;
        final service = DatabaseEncryptionServiceIo(
          keyService: keyService,
          directoryResolver: () async => tempDir.path,
        );
        final plan = await service.prepare();
        expect(plan, isNotNull);
        expect(plan!.freshInstall, isTrue);
        expect(plan.key, hasLength(32));
        // Nenhum arquivo criado ainda — a criação do banco é do openDatabase.
        expect(File('${tempDir.path}/$encryptedName').existsSync(), isFalse);
      },
    );
  });

  group('DatabaseService ponta a ponta com criptografia', () {
    test('instalação nova → banco criptografado v11 → persistência após '
        'fechar e reabrir', () async {
      DatabaseKeyService.resetInstanceForTesting(
        store: InMemoryDatabaseKeyStore(),
      );
      final keyService = DatabaseKeyService.instance;
      final service = DatabaseEncryptionServiceIo(
        keyService: keyService,
        directoryResolver: () async => tempDir.path,
      );
      DatabaseService.encryptionServiceOverride = service;

      final db = await DatabaseService.instance.database;
      // Grava um registro real pela API do app.
      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert('treatments', {
        'id': 'trt-e2e',
        'name': 'Omeprazol 20mg',
        'dosage': '1 cápsula',
        'presentation': '',
        'instructions': 'Em jejum',
        'start_date': '2026-04-01',
        'frequency': 'daily',
        'dose_times': '["07:30"]',
        'is_archived': 0,
        'created_at': now,
        'updated_at': now,
      });
      await DatabaseService.instance.close();

      // O arquivo ativo é o criptografado, sem header plaintext.
      final encFile = File('${tempDir.path}/$encryptedName');
      expect(encFile.existsSync(), isTrue);
      expect(
        detectSqliteFileFormat(encFile.path),
        DatabaseFileFormat.encryptedOrUnknown,
      );

      // Reabre e valida persistência.
      final reopened = await DatabaseService.instance.database;
      final rows = await reopened.query('treatments');
      expect(rows.single['name'], 'Omeprazol 20mg');
      await DatabaseService.instance.close();

      DatabaseService.encryptionServiceOverride = null;
      DatabaseKeyService.instanceOverride = null;
    });
  });
}

/// Cofre que falha ao ler: simula envelope/Keystore ausente ou corrompido
/// com um wrap que existe parcialmente (cenário de recuperação obrigatória).
class _BrokenKeyStore implements DatabaseKeyStore {
  @override
  Future<List<int>?> readKey() async {
    throw const DatabaseKeyRecoveryRequiredException(
      'Chave incompleta: restaure o envelope de recuperação.',
    );
  }

  @override
  Future<bool> createKeyIfAbsent(List<int> key) async {
    throw const DatabaseKeyRecoveryRequiredException(
      'Chave incompleta: restaure o envelope de recuperação.',
    );
  }

  @override
  Future<void> deleteKey() async {}
}
