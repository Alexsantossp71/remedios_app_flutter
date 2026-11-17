import 'dart:io';
import 'dart:math';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

String newTestKey() {
  final random = Random.secure();
  return List<int>.generate(
    32,
    (_) => random.nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

Future<Database> openEncrypted(String path, String key) {
  return databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 1,
      onConfigure: (db) async {
        await db.execute("PRAGMA cipher = 'chacha20'");
        await db.execute('''PRAGMA key = "x'$key'"''');
        // Force key validation before sqflite reads schema/version metadata.
        await db.rawQuery('SELECT count(*) FROM sqlite_master');
      },
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE poc_records (id INTEGER PRIMARY KEY, value TEXT NOT NULL)',
        );
      },
    ),
  );
}

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory directory;
  late String path;
  late String key;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('sqflite-sqlite3mc-');
    path = '${directory.path}/encrypted.db';
    key = newTestKey();
  });

  tearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  test('sqflite FFI creates, writes and reopens an encrypted database', () async {
    final db = await openEncrypted(path, key);
    await db.insert('poc_records', {'value': 'synthetic test record'});
    await db.close();

    final bytes = File(path).readAsBytesSync();
    expect(bytes.length, greaterThan(32));
    expect(
      String.fromCharCodes(bytes.take(16)),
      isNot(equals('SQLite format 3\\u0000')),
    );

    final reopened = await openEncrypted(path, key);
    final rows = await reopened.query('poc_records');
    expect(rows.single['value'], 'synthetic test record');
    await reopened.close();
  });

  test('sqflite FFI rejects a wrong key during onConfigure', () async {
    final db = await openEncrypted(path, key);
    await db.insert('poc_records', {'value': 'secret synthetic record'});
    await db.close();

    final wrongKey = newTestKey();
    await expectLater(openEncrypted(path, wrongKey), throwsA(anything));
  });
}
