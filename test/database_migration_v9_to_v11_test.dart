import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:remedios_app_flutter/services/database_service.dart';

/// Testes de migração de schema do SQLite (P2-5 + P2-8).
///
/// P2-5: valida trilha v9 → v11 com dados fictícios em todas as tabelas.
/// P2-8: valida retomada de migração interrompida (criou tabela mas
/// parou antes de bumpar user_version). Bug real corrigido no commit
/// anterior: _onUpgrade agora usa CREATE TABLE IF NOT EXISTS.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DatabaseService dbService;

  Future<Database> seedV9Database(String path) async {
    return openDatabase(
      path,
      version: 9,
      onCreate: (newDb, version) async {
        await newDb.execute('''
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
        await newDb.insert('treatments', {
          'id': 'v9-treat-1',
          'name': 'Dipirona 500mg',
          'dosage': '500mg',
          'presentation': 'Comprimido',
          'instructions': 'Tomar com água',
          'start_date': '2026-01-01T08:00:00.000Z',
          'frequency': 'daily',
          'dose_times': '[{"hour":8,"minute":0}]',
          'is_archived': 0,
          'created_at': '2026-01-01T00:00:00.000Z',
          'updated_at': '2026-01-01T00:00:00.000Z',
        });
      },
    );
  }

  setUp(() async {
    dbService = DatabaseService.instance;
    // Inicializa factory FFI globalmente.
    await dbService.initInMemoryDatabase();
  });

  group('P2-5: Migração v9 → v11 round-trip', () {
    test('Aplica _onUpgrade(9→11) sem perda de dados', () async {
      final dir = Directory.systemTemp.createTempSync('legacy_v9');
      final path = '${dir.path}/v9.db';
      final db = await seedV9Database(path);

      await dbService.applyUpgradesForTesting(db, 9);

      // v10 criou lab_results — deve existir.
      final labTables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='lab_results'",
      );
      expect(labTables, hasLength(1), reason: 'lab_results não foi criada');

      // v11 adicionou colunas de prescriber em treatments.
      final cols = await db.rawQuery('PRAGMA table_info(treatments)');
      final names = cols.map((c) => c['name']).toList();
      for (final expected in [
        'prescriber_doctor_id',
        'prescriber_name',
        'prescriber_crm',
        'prescriber_crm_state',
        'prescribed_on',
      ]) {
        expect(names, contains(expected), reason: 'faltou coluna $expected');
      }

      // treatment_prescriptions + index.
      final prescriptionTables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='treatment_prescriptions'",
      );
      expect(prescriptionTables, hasLength(1));

      // Dado legacy sobrevive.
      final treatments = await db.query('treatments');
      expect(treatments, hasLength(1));
      expect(treatments.first['name'], 'Dipirona 500mg');
      expect(treatments.first['prescriber_name'], isNull);

      await db.close();
    });
  });

  group('P2-8: Migração interrompida e retomada', () {
    test(
      'Banco v9 parcialmente migrado (parou em v10) retoma para v11 sem perda',
      () async {
        // Cenário: app rodou v9→10 (criou lab_results), crashou antes do
        // v11 (sem colunas prescriber). Reabrir + aplicar _onUpgrade(9→11)
        // deve completar sem duplicar tabelas nem perder dados.

        final dir = Directory.systemTemp.createTempSync('legacy_v9_partial');
        final path = '${dir.path}/v9_partial.db';
        var db = await seedV9Database(path);

        // Simula v9→10 parcial: cria lab_results manualmente.
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
        await db.insert('lab_results', {
          'id': 'v9-lab-1',
          'date': '2026-03-01T00:00:00.000Z',
          'lab_name': 'Laboratório Central',
          'values_json': '[{"marker":"glicemia","value":92,"unit":"mg/dL"}]',
          'created_at': '2026-03-01T00:00:00.000Z',
          'updated_at': '2026-03-01T00:00:00.000Z',
        });
        await db.close();

        // Reabre o mesmo arquivo. user_version ainda é 9.
        db = await openDatabase(path, version: 11);

        // Aplica _onUpgrade(9→11). Bloco < 10 tenta CREATE TABLE
        // lab_results — já existe, mas agora usa IF NOT EXISTS (fix do
        // commit anterior), então não falha.
        await dbService.applyUpgradesForTesting(db, 9);

        // Valida estado final v11.
        final labResults = await db.query('lab_results');
        expect(labResults, hasLength(1));
        expect(labResults.first['id'], 'v9-lab-1');
        expect(labResults.first['lab_name'], 'Laboratório Central');

        // Dados legacy sobreviveram.
        final treatments = await db.query('treatments');
        expect(treatments, hasLength(1));
        expect(treatments.first['name'], 'Dipirona 500mg');

        // Colunas de prescriber foram adicionadas.
        final cols = await db.rawQuery('PRAGMA table_info(treatments)');
        expect(
          cols.map((c) => c['name']).toList(),
          containsAll([
            'prescriber_doctor_id',
            'prescriber_name',
            'prescribed_on',
          ]),
        );

        // treatment_prescriptions foi criada.
        final prescriptionTables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='treatment_prescriptions'",
        );
        expect(prescriptionTables, hasLength(1));

        await db.close();
      },
    );
  });
}
