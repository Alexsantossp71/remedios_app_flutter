import 'dart:convert';
import 'dart:math';

import 'package:sqlite3/sqlite3.dart';

/// Minimal native-only proof of concept. This is not the app's database layer
/// and deliberately does not persist or manage encryption keys.
class EncryptedDatabasePoc {
  EncryptedDatabasePoc._();

  static String generateTestKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static Database open({required String path, required String key}) {
    if (key.length < 32) {
      throw ArgumentError.value(key.length, 'key.length', 'Key is too short');
    }

    final db = sqlite3.open(path);
    try {
      // SQLite3MultipleCiphers defaults are made explicit so the file format
      // does not silently depend on a library default changing.
      db.execute("PRAGMA cipher = 'sqlcipher'");
      db.execute('PRAGMA legacy = 4');
      final keyHex = key.codeUnits
          .map((unit) => unit.toRadixString(16).padLeft(2, '0'))
          .join();
      db.execute("PRAGMA key = \"x'$keyHex'\"");
      // Force key verification immediately, before returning the handle.
      db.select('SELECT count(*) FROM sqlite_master');
      return db;
    } catch (_) {
      db.dispose();
      rethrow;
    }
  }
}
