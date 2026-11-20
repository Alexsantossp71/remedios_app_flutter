/// Envelope tipado do arquivo de backup (P2-4 da auditoria arquitetural).
///
/// O formato em disco continua sendo o mesmo JSON estável e independente de
/// modelo — backups antigos continuam restauráveis byte a byte. O envelope
/// tipa a fronteira do serviço em memória: `BackupService.exportAll()` devolve
/// um [BackupEnvelope] e `restore` passa a consumir o tipo, eliminando o
/// vazamento de `Map<String, dynamic>` na API pública.
class BackupEnvelope {
  const BackupEnvelope({
    required this.formatVersion,
    required this.schemaVersion,
    required this.exportedAt,
    required this.tables,
  });

  /// Marcador de origem: arquivos de outros apps/JSONs soltos são rejeitados.
  static const String appMarker = 'remedios-app';

  /// Versão do formato do arquivo de backup (independe do schema do banco).
  static const int currentFormatVersion = 1;

  /// Versão do schema de dados incluído no backup. Acompanha a versão
  /// atual do banco; versões antigas continuam aceitas na restauração.
  static const int maxSchemaVersion = 11;

  final int formatVersion;
  final int schemaVersion;

  /// Carimbo de data/hora da exportação (serializado em UTC no JSON).
  final DateTime exportedAt;

  /// Linhas brutas por tabela (pais antes de filhos na restauração — a
  /// ordem de inserção é responsabilidade do [BackupService]).
  final Map<String, List<Map<String, dynamic>>> tables;

  /// Serializa para o mapa JSON do formato estável do arquivo de backup.
  Map<String, dynamic> toJson() => {
    'app': appMarker,
    'formatVersion': formatVersion,
    'schemaVersion': schemaVersion,
    'exportedAt': exportedAt.toUtc().toIso8601String(),
    'tables': tables,
  };

  /// Faz o parse de um backup decodificado (ex.: `jsonDecode` de um arquivo)
  /// validando marcador, versões e estrutura das tabelas.
  ///
  /// Lança [BackupFormatException] quando o arquivo não é um backup válido
  /// deste app, é de formato/schema mais novo que o app suporta, ou tem
  /// estrutura de tabela inválida. As chaves de integridade por linha
  /// (PKs/FKs) são validadas pelo `BackupService.restore`, que conhece a
  /// ordem e a dependência entre tabelas.
  factory BackupEnvelope.fromJson(Map<String, dynamic> raw) {
    if (raw['app'] != appMarker) {
      throw const BackupFormatException(
        'Este arquivo não é um backup do Remédio na Hora.',
      );
    }

    final format = _readInt(raw['formatVersion']);
    if (format == null || format > currentFormatVersion) {
      throw BackupFormatException(
        'Formato de backup ($format) é mais novo que este app suporta '
        '($currentFormatVersion). Atualize o app.',
      );
    }

    final schema = _readInt(raw['schemaVersion']);
    if (schema == null || schema > maxSchemaVersion) {
      throw BackupFormatException(
        'O backup foi feito por uma versão mais nova do app '
        '(schema $schema > $maxSchemaVersion). Atualize o app.',
      );
    }

    final rawTables = raw['tables'];
    final tables = <String, List<Map<String, dynamic>>>{};
    if (rawTables != null) {
      if (rawTables is! Map) {
        throw const BackupFormatException('"tables" deveria ser um objeto.');
      }
      rawTables.cast<String, dynamic>().forEach((table, value) {
        if (value is! List) {
          throw BackupFormatException('"tables.$table" deveria ser uma lista.');
        }
        final rows = <Map<String, dynamic>>[];
        for (var i = 0; i < value.length; i++) {
          final row = value[i];
          if (row is! Map) {
            throw BackupFormatException(
              'Linha $i de "$table" não é um objeto JSON.',
            );
          }
          rows.add(row.cast<String, dynamic>());
        }
        tables[table] = rows;
      });
    }

    final exportedAtRaw = raw['exportedAt'];
    final exportedAt = exportedAtRaw is String
        ? DateTime.tryParse(exportedAtRaw)
        : null;

    return BackupEnvelope(
      formatVersion: format,
      schemaVersion: schema,
      // Backups antigos de versões anteriores ao carimbo restauram igual;
      // o campo é informativo e não participa da validação.
      exportedAt: exportedAt ?? DateTime.now(),
      tables: tables,
    );
  }

  static int? _readInt(dynamic value) => value is int ? value : null;
}

/// O arquivo não é um backup válido deste app.
class BackupFormatException implements Exception {
  const BackupFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}
