/// Preservation snapshots used to prove that a database migration did not
/// lose data.
///
/// For every schema table the snapshot records the row count and the full set
/// of primary keys. Comparing before/after snapshots is a hard gate of the
/// encryption migration: any difference aborts the migration and leaves the
/// original database untouched.
class TableSnapshot {
  const TableSnapshot({
    required this.table,
    required this.count,
    required this.ids,
  });

  final String table;
  final int count;
  final Set<String> ids;

  Map<String, Object?> toJson() => {
    'table': table,
    'count': count,
    'ids': ids.toList()..sort(),
  };

  static TableSnapshot fromJson(Map<String, Object?> json) => TableSnapshot(
    table: json['table']! as String,
    count: json['count']! as int,
    ids: (json['ids']! as List<Object?>).cast<String>().toSet(),
  );
}

/// Reads rows for a SQL query. Implemented over raw `sqlite3` connections
/// (native migration) and `sqflite` databases (web migration).
typedef RowSelector = Future<List<Map<String, Object?>>> Function(String query);

/// The tables of schema version 11 in foreign-key-safe copy order
/// (parents before children).
const List<String> databaseV11Tables = <String>[
  'treatments',
  'doctors',
  'health_plans',
  'user_profile',
  'emergency_contacts',
  'exams',
  'consultations',
  'dose_events',
  'treatment_prescriptions',
  'lab_results',
];

class DatabasePreservation {
  DatabasePreservation._();

  /// Snapshots [tables] (defaults to the v11 set) using [selector].
  static Future<Map<String, TableSnapshot>> snapshotTables(
    RowSelector selector, {
    List<String>? tables,
  }) async {
    final result = <String, TableSnapshot>{};
    for (final table in tables ?? databaseV11Tables) {
      final rows = await selector('SELECT id FROM "$table"');
      final ids = rows
          .map((row) => row['id'])
          .whereType<Object?>()
          .map((id) => id.toString())
          .toSet();
      result[table] = TableSnapshot(table: table, count: rows.length, ids: ids);
    }
    return result;
  }

  /// Compares two snapshots. Returns the list of mismatches (empty means
  /// identical preservation).
  static List<String> compare(
    Map<String, TableSnapshot> before,
    Map<String, TableSnapshot> after,
  ) {
    final problems = <String>[];
    for (final entry in before.entries) {
      final afterSnapshot = after[entry.key];
      if (afterSnapshot == null) {
        problems.add('Tabela ${entry.key} ausente no banco de destino.');
        continue;
      }
      if (entry.value.count != afterSnapshot.count) {
        problems.add(
          'Tabela ${entry.key}: ${entry.value.count} registros antes, '
          '${afterSnapshot.count} depois.',
        );
      }
      final missing = entry.value.ids.difference(afterSnapshot.ids);
      final extra = afterSnapshot.ids.difference(entry.value.ids);
      for (final id in missing.take(5)) {
        problems.add('Tabela ${entry.key}: registro $id ausente no destino.');
      }
      if (missing.length > 5) {
        problems.add(
          'Tabela ${entry.key}: mais ${missing.length - 5} registros ausentes.',
        );
      }
      for (final id in extra.take(5)) {
        problems.add(
          'Tabela ${entry.key}: registro inesperado $id no destino.',
        );
      }
      if (extra.length > 5) {
        problems.add(
          'Tabela ${entry.key}: mais ${extra.length - 5} registros inesperados.',
        );
      }
    }
    for (final key in after.keys) {
      if (!before.containsKey(key)) {
        problems.add('Tabela $key inesperada no banco de destino.');
      }
    }
    return problems;
  }

  /// Builds a compact JSON-safe map for audit records (no row contents, only
  /// counts).
  static Map<String, Object?> countsForAudit(
    Map<String, TableSnapshot> snapshot,
  ) {
    return snapshot.map((table, snap) => MapEntry(table, snap.count));
  }
}

/// Selector over a raw `package:sqlite3` database connection.
///
/// Typed as `dynamic` to avoid importing `package:sqlite3` here: on web the
/// connection comes from `package:sqlite3/wasm.dart` and on the VM from the
/// native assets build. Only `select` is invoked.
RowSelector rawSqliteRowSelector(dynamic sqlite3Database) {
  return (query) async {
    final rows = sqlite3Database.select(query) as List<dynamic>;
    return rows
        .map<Map<String, Object?>>(
          (row) => (row as Map<dynamic, dynamic>).cast<String, Object?>(),
        )
        .toList();
  };
}

/// Selector over a `sqflite` database (any factory: ffi or web).
RowSelector sqfliteRowSelector(dynamic sqfliteDatabase) {
  return (query) async {
    final rows =
        await (sqfliteDatabase.rawQuery(query) as Future<List<dynamic>>);
    return rows.cast<Map<String, Object?>>();
  };
}
