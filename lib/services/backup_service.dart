import 'package:sqflite/sqflite.dart';

import 'database_service.dart';

/// Serviço de backup/restauração de todos os dados do app em JSON.
///
/// O app é offline-first: tudo vive no SQLite do dispositivo (IndexedDB na
/// web). Sem backup, limpar os dados do navegador ou trocar de aparelho
/// significa perder todo o histórico de medicação — para dados de saúde,
/// isso é inaceitável. Este serviço exporta as 7 tabelas cruas (round-trip
/// exato: linha de volta para linha) e as restaura numa única transação.
///
/// O formato é independente de modelo: exporta as linhas do banco como
/// estão, de modo que novas colunas não quebrem backups antigos (colunas
/// novas vêm vazias ao restaurar um backup antigo, respeitando os DEFAULTs).
class BackupService {
  BackupService({DatabaseService? dbService})
      : _dbService = dbService ?? DatabaseService.instance;

  final DatabaseService _dbService;

  /// Singleton padrão usado pela UI.
  static final BackupService instance = BackupService();

  /// Versão do formato do arquivo de backup (independe do schema do banco).
  static const int backupFormatVersion = 1;

  /// Marcador de origem: arquivos de outros apps/JSONs soltos são rejeitados.
  static const String appMarker = 'remedios-app';

  /// Espelha `DatabaseService._databaseVersion` (v7). Backups com schema
  /// mais novo que o app não podem ser restaurados com segurança.
  static const int maxSchemaVersion = 7;

  /// Ordem de INSERÇÃO (pais antes de filhos, para respeitar foreign keys).
  static const List<String> _tableOrder = [
    'treatments',
    'dose_events',
    'doctors',
    'consultations',
    'health_plans',
    'user_profile',
    'emergency_contacts',
  ];

  /// Ordem de EXCLUSÃO (filhos antes de pais).
  static const List<String> _deleteOrder = [
    'dose_events',
    'consultations',
    'emergency_contacts',
    'user_profile',
    'health_plans',
    'doctors',
    'treatments',
  ];

  /// Chaves obrigatórias por tabela (PKs e FKs que dão integridade mínima).
  static const Map<String, List<String>> _requiredKeys = {
    'treatments': ['id'],
    'dose_events': ['id', 'treatment_id'],
    'doctors': ['id'],
    'consultations': ['id', 'doctor_id'],
    'health_plans': ['id'],
    'user_profile': ['id'],
    'emergency_contacts': ['id'],
  };

  /// Nome de arquivo padrão do backup exportado.
  static String backupFileName({DateTime? at}) {
    final t = at ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${t.year}${two(t.month)}${two(t.day)}';
    final time = '${two(t.hour)}${two(t.minute)}${two(t.second)}';
    return 'remedios-backup-$date-$time.json';
  }

  /// Exporta todas as tabelas para o mapa serializável em JSON.
  Future<Map<String, dynamic>> exportAll() async {
    final db = await _dbService.database;
    final tables = <String, List<Map<String, dynamic>>>{};
    for (final table in _tableOrder) {
      tables[table] = await db.query(table);
    }
    return {
      'app': appMarker,
      'formatVersion': backupFormatVersion,
      'schemaVersion': maxSchemaVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'tables': tables,
    };
  }

  /// Valida e restaura um backup, substituindo TODO o conteúdo atual do
  /// banco numa única transação (ou tudo entra, ou nada muda).
  ///
  /// Lança [BackupFormatException] quando o arquivo não é um backup válido
  /// deste app, é de formato/schema mais novo que o app suporta, ou tem
  /// linhas sem as chaves de integridade mínima.
  Future<RestoreSummary> restore(Map<String, dynamic> backup) async {
    _validate(backup);

    final rawTables = (backup['tables'] as Map?)?.cast<String, dynamic>() ?? {};
    final rowsByTable = <String, List<Map<String, dynamic>>>{};
    for (final table in _tableOrder) {
      final rawRows = rawTables[table];
      if (rawRows == null) {
        rowsByTable[table] = const [];
        continue;
      }
      if (rawRows is! List) {
        throw BackupFormatException('"tables.$table" deveria ser uma lista.');
      }
      final required = _requiredKeys[table]!;
      final rows = <Map<String, dynamic>>[];
      for (var i = 0; i < rawRows.length; i++) {
        final row = rawRows[i];
        if (row is! Map) {
          throw BackupFormatException(
              'Linha $i de "$table" não é um objeto JSON.');
        }
        final map = row.cast<String, dynamic>();
        for (final key in required) {
          final value = map[key];
          if (value == null || (value is String && value.isEmpty)) {
            throw BackupFormatException(
                'Linha $i de "$table" está sem "$key" (obrigatório).');
          }
        }
        rows.add(map);
      }
      rowsByTable[table] = rows;
    }

    final db = await _dbService.database;
    await db.transaction((txn) async {
      for (final table in _deleteOrder) {
        await txn.delete(table);
      }
      for (final table in _tableOrder) {
        for (final row in rowsByTable[table]!) {
          await txn.insert(
            table,
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });

    return RestoreSummary(
      treatments: rowsByTable['treatments']!.length,
      doseEvents: rowsByTable['dose_events']!.length,
      doctors: rowsByTable['doctors']!.length,
      consultations: rowsByTable['consultations']!.length,
      healthPlans: rowsByTable['health_plans']!.length,
      hasUserProfile: rowsByTable['user_profile']!.isNotEmpty,
      emergencyContacts: rowsByTable['emergency_contacts']!.length,
    );
  }

  void _validate(Map<String, dynamic> backup) {
    if (backup['app'] != appMarker) {
      throw BackupFormatException(
          'Este arquivo não é um backup do Remédio na Hora.');
    }

    final format = _readInt(backup['formatVersion']);
    if (format == null || format > backupFormatVersion) {
      throw BackupFormatException(
          'Formato de backup ($format) é mais novo que este app suporta '
          '($backupFormatVersion). Atualize o app.');
    }

    final schema = _readInt(backup['schemaVersion']);
    if (schema == null || schema > maxSchemaVersion) {
      throw BackupFormatException(
          'O backup foi feito por uma versão mais nova do app '
          '(schema $schema > $maxSchemaVersion). Atualize o app.');
    }
  }

  int? _readInt(dynamic value) => value is int ? value : null;
}

/// Resumo do que foi restaurado, para feedback na UI.
class RestoreSummary {
  const RestoreSummary({
    required this.treatments,
    required this.doseEvents,
    required this.doctors,
    required this.consultations,
    required this.healthPlans,
    required this.hasUserProfile,
    required this.emergencyContacts,
  });

  final int treatments;
  final int doseEvents;
  final int doctors;
  final int consultations;
  final int healthPlans;
  final bool hasUserProfile;
  final int emergencyContacts;

  /// Texto curto em pt-BR com os contadores não nulos, ex.:
  /// "3 tratamentos, 45 doses, 2 médicos".
  String describe() {
    final parts = <String>[];
    if (treatments > 0) parts.add('$treatments tratamentos');
    if (doseEvents > 0) parts.add('$doseEvents doses');
    if (doctors > 0) parts.add('$doctors médicos');
    if (consultations > 0) parts.add('$consultations consultas');
    if (healthPlans > 0) parts.add('$healthPlans planos');
    if (hasUserProfile) parts.add('perfil');
    if (emergencyContacts > 0) {
      parts.add('$emergencyContacts contatos de emergência');
    }
    return parts.isEmpty ? 'nenhum registro' : parts.join(', ');
  }
}

/// O arquivo não é um backup válido deste app.
class BackupFormatException implements Exception {
  const BackupFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}
