import 'dart:html' as html;

import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

const _key =
    '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';
const _wrongKey =
    'ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100';
const _databaseName = 'sqlite3mc-sqflite-web-poc.db';

Future<Database> _openEncrypted(String key) {
  return databaseFactoryFfiWeb.openDatabase(
    _databaseName,
    options: OpenDatabaseOptions(
      version: 1,
      onConfigure: (db) async {
        await db.execute("PRAGMA cipher = 'chacha20'");
        await db.execute('''PRAGMA key = "x'$key'"''');
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

Future<void> main() async {
  final output = html.document.querySelector('#result');
  final mode = Uri.base.queryParameters['mode'] ?? 'write';

  try {
    if (mode == 'wrong-key') {
      var rejected = false;
      try {
        final db = await _openEncrypted(_wrongKey);
        await db.query('poc_records');
        await db.close();
      } catch (_) {
        rejected = true;
      }
      if (!rejected) {
        throw StateError('sqflite Web accepted an incorrect database key.');
      }
      output?.text = 'PASS: wrong key rejected by sqflite Web';
      return;
    }

    final db = await _openEncrypted(_key);
    if (mode == 'write') {
      await db.insert('poc_records', {
        'value': 'encrypted record through sqflite Web API',
      });
      output?.text = 'PASS: encrypted record written through sqflite Web API';
    } else if (mode == 'verify') {
      final rows = await db.query('poc_records');
      if (rows.length != 1 ||
          rows.single['value'] !=
              'encrypted record through sqflite Web API') {
        throw StateError('Encrypted record was not recovered.');
      }
      output?.text = 'PASS: encrypted record recovered through sqflite Web API';
    } else {
      throw ArgumentError.value(mode, 'mode', 'Unknown test mode');
    }
    await db.close();
  } catch (error, stack) {
    output?.text = 'FAIL: $error\n$stack';
  }
}
