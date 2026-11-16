import 'dart:io';
import 'dart:math';

import 'package:sqlite3mc_poc/encrypted_database_poc.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late String databasePath;
  late String key;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('sqlite3mc-poc-');
    databasePath = '${directory.path}/medical-data.db';
    key = EncryptedDatabasePoc.generateTestKey();
  });

  tearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  test('encrypts the file and reopens with the same key', () {
    final db = EncryptedDatabasePoc.open(path: databasePath, key: key);
    db.execute('CREATE TABLE sample (id INTEGER PRIMARY KEY, value TEXT NOT NULL)');
    db.execute("INSERT INTO sample(value) VALUES ('fictional test record')");
    db.dispose();

    final bytes = File(databasePath).readAsBytesSync();
    expect(bytes.length, greaterThan(32));
    expect(
      String.fromCharCodes(bytes.take(16)),
      isNot(equals('SQLite format 3\u0000')),
      reason: 'An encrypted SQLite file must not expose the plaintext header.',
    );

    final reopened = EncryptedDatabasePoc.open(path: databasePath, key: key);
    expect(reopened.select('SELECT value FROM sample').single['value'],
        'fictional test record');
    reopened.dispose();
  });

  test('rejects a wrong key before exposing database records', () {
    final db = EncryptedDatabasePoc.open(path: databasePath, key: key);
    db.execute('CREATE TABLE sample (secret TEXT NOT NULL)');
    db.execute("INSERT INTO sample(secret) VALUES ('not for plaintext')");
    db.dispose();

    final wrongKey = List<int>.generate(32, (_) => Random.secure().nextInt(256))
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();

    expect(
      () => EncryptedDatabasePoc.open(path: databasePath, key: wrongKey)
          .select('SELECT * FROM sample'),
      throwsA(anything),
    );
  });

  test('refuses an obviously short key', () {
    expect(
      () => EncryptedDatabasePoc.open(path: databasePath, key: 'short'),
      throwsArgumentError,
    );
  });
}
