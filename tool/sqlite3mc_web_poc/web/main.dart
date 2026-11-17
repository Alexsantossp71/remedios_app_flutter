import 'dart:convert';
import 'dart:html' as html;

import 'package:sqlite3/wasm.dart';

const _databaseName = 'remedios-hora-sqlite3mc-poc';
const _databasePath = '/browser-poc.db';
// Fictional test-only key. Never reuse this pattern or key in the application.
const _testKey = 'only-a-public-fictional-browser-poc-key';

String _toHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void _setKey(CommonDatabase db, String key) {
  final keyHex = _toHex(utf8.encode(key));
  db.execute("PRAGMA cipher = 'sqlcipher'");
  db.execute('PRAGMA legacy = 4');
  db.execute('PRAGMA key = "x\'$keyHex\'"');
  // Force authentication now, rather than on the first application query.
  db.select('SELECT count(*) FROM sqlite_master');
}

Future<void> main() async {
  final output = html.querySelector('#result')!;
  try {
    final sqlite = await WasmSqlite3.loadFromUrlString('sqlite3mc.wasm');
    final fileSystem = await IndexedDbFileSystem.open(dbName: _databaseName);
    sqlite.registerVirtualFileSystem(fileSystem, makeDefault: true);

    // Create/write on the first visit; the same row must survive a full reload.
    var db = sqlite.open(_databasePath);
    _setKey(db, _testKey);
    db.execute('CREATE TABLE IF NOT EXISTS poc_records '
        '(id INTEGER PRIMARY KEY, value TEXT NOT NULL)');
    db.execute(
      "INSERT OR IGNORE INTO poc_records(id, value) VALUES "
      "(1, 'fictional browser persistence record')",
    );
    db.dispose();
    await fileSystem.flush();

    // Reopen the persisted IndexedDB-backed file with the correct key.
    db = sqlite.open(_databasePath);
    _setKey(db, _testKey);
    final rows = db.select('SELECT value FROM poc_records WHERE id = 1');
    if (rows.length != 1 ||
        rows.single['value'] != 'fictional browser persistence record') {
      throw StateError('Correct-key reopen did not return the test record.');
    }
    db.dispose();

    // A wrong key must fail before the table can be read.
    final wrongKeyDb = sqlite.open(_databasePath);
    var wrongKeyRejected = false;
    try {
      _setKey(wrongKeyDb, 'deliberately-wrong-test-key');
      wrongKeyDb.select('SELECT value FROM poc_records');
    } catch (_) {
      wrongKeyRejected = true;
    } finally {
      wrongKeyDb.dispose();
    }
    if (!wrongKeyRejected) {
      throw StateError('The browser accepted an incorrect encryption key.');
    }

    await fileSystem.flush();
    output.text = 'PASS: encrypted WASM, IndexedDB persistence, correct-key '
        'reopen and wrong-key rejection';
  } catch (error, stack) {
    output.text = 'FAIL: $error\n$stack';
    rethrow;
  }
}
