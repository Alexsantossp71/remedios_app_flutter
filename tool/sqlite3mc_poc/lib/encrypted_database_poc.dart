import 'dart:math';

import 'package:sqlite3/sqlite3.dart';

/// Minimal native-only proof of concept. This is not the app's database layer
/// and deliberately does not persist or manage encryption keys.
class EncryptedDatabasePoc {
  EncryptedDatabasePoc._();

  /// Returns a 256-bit test key encoded as 64 lowercase hexadecimal chars.
  static String generateTestKey() {
    final random = Random.secure();
    return List<int>.generate(
      32,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  static Database open({required String path, required String key}) {
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(key)) {
      throw ArgumentError.value(
        key.length,
        'key.length',
        'Key must be exactly 32 bytes encoded as 64 hexadecimal characters',
      );
    }

    final db = sqlite3.open(path);
    try {
      // Keep cipher and legacy format identical to the Web POC.
      db.execute("PRAGMA cipher = 'sqlcipher'");
      db.execute('PRAGMA legacy = 4');
      db.execute('''PRAGMA key = "x'$key'"''');
      // Force key verification immediately, before returning the handle.
      db.select('SELECT count(*) FROM sqlite_master');
      return db;
    } catch (_) {
      db.dispose();
      rethrow;
    }
  }
}
