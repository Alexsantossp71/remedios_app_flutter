import 'dart:convert';
import 'dart:html' as html;

import 'package:sqlite3/common.dart';
import 'package:sqlite3/wasm.dart';

const _databasePath = '/browser-poc.db';
// Fictional test-only key. Never reuse this pattern or key in the application.
const _testKey = 'only-a-public-fictional-browser-poc-key';

String _toHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void _setKey(CommonDatabase db, String key) {
  final keyHex = _toHex(utf8.encode(key));
  // The published sqlite3mc.wasm build uses ChaCha20 (sqleet) by default.
  db.execute("PRAGMA cipher = 'chacha20'");
  db.execute('PRAGMA key = "x\'$keyHex\'"');
  // Force authentication now, rather than on the first application query.
  db.select('SELECT count(*) FROM sqlite_master');
}

Future<void> main() async {
  final output = html.querySelector('#result')!;
  try {
    final sqlite = await WasmSqlite3.loadFromUrlString('sqlite3mc.wasm');
    // The sqlite3 package's documented SQLite3MC Web example uses the
    // in-memory VFS. IndexedDbFileSystem currently rejects SQLITE_FCNTL_CIPHER
    // ("Encryption is not supported by the VFS"), so it is not used here.
    final fileSystem = InMemoryFileSystem();
    sqlite.registerVirtualFileSystem(fileSystem, makeDefault: true);

    var db = sqlite.open(_databasePath);
    _setKey(db, _testKey);
    db.execute('CREATE TABLE poc_records '
        '(id INTEGER PRIMARY KEY, value TEXT NOT NULL)');
    db.execute(
      "INSERT INTO poc_records(id, value) VALUES "
      "(1, 'fictional browser encryption record')",
    );
    db.close();

    // Reopen the same encrypted file in the same browser memory VFS.
    db = sqlite.open(_databasePath);
    _setKey(db, _testKey);
    final rows = db.select('SELECT value FROM poc_records WHERE id = 1');
    if (rows.length != 1 ||
        rows.single['value'] != 'fictional browser encryption record') {
      throw StateError('Correct-key reopen did not return the test record.');
    }
    db.close();

    // A wrong key must fail before the table can be read.
    final wrongKeyDb = sqlite.open(_databasePath);
    var wrongKeyRejected = false;
    try {
      _setKey(wrongKeyDb, 'deliberately-wrong-test-key');
      wrongKeyDb.select('SELECT value FROM poc_records');
    } catch (_) {
      wrongKeyRejected = true;
    } finally {
      wrongKeyDb.close();
    }
    if (!wrongKeyRejected) {
      throw StateError('The browser accepted an incorrect encryption key.');
    }

    output.text = 'PASS: SQLite3MC WASM encryption, correct-key reopen and '
        'wrong-key rejection in Chromium';
  } catch (error, stack) {
    output.text = 'FAIL: $error\n$stack';
  }
}
