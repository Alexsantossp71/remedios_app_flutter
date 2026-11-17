import 'dart:html' as html;

import 'package:sqlite3/common.dart';
import 'package:sqlite3/wasm.dart';

const _databasePath = '/browser-poc.db';
// Fictional test-only key. Never reuse this pattern or key in the application.
const _testKey = 'only-a-public-fictional-browser-poc-key';

void _setKey(CommonDatabase db, String key) {
  // Match the official package README example: a UTF-8 passphrase.
  db.execute("PRAGMA key = '$key'");
  // Force authentication now, rather than on the first application query.
  db.select('SELECT count(*) FROM sqlite_master');
}

Future<void> main() async {
  final output = html.querySelector('#result')!;
  try {
    final sqlite = await WasmSqlite3.loadFromUrlString('sqlite3mc.wasm');
    // SQLite3MultipleCiphers wraps the registered VFS. Do not make the
    // underlying VFS default: open through its multipleciphers-* wrapper.
    // SQLite3MC requires the multipleciphers-<vfs-name> wrapper; simply
    // registering the underlying VFS as default bypasses encryption.
    final fileSystem = InMemoryFileSystem();
    sqlite.registerVirtualFileSystem(fileSystem);
    final encryptedVfs = 'multipleciphers-${fileSystem.name}';

    var db = sqlite.open(_databasePath, vfs: encryptedVfs);
    _setKey(db, _testKey);
    db.execute('CREATE TABLE poc_records '
        '(id INTEGER PRIMARY KEY, value TEXT NOT NULL)');
    db.execute(
      "INSERT INTO poc_records(id, value) VALUES "
      "(1, 'fictional browser encryption record')",
    );
    db.close();

    // Reopen the same encrypted file in the same browser memory VFS.
    db = sqlite.open(_databasePath, vfs: encryptedVfs);
    _setKey(db, _testKey);
    final rows = db.select('SELECT value FROM poc_records WHERE id = 1');
    if (rows.length != 1 ||
        rows.single['value'] != 'fictional browser encryption record') {
      throw StateError('Correct-key reopen did not return the test record.');
    }
    db.close();

    // A wrong key must fail before the table can be read.
    final wrongKeyDb = sqlite.open(_databasePath, vfs: encryptedVfs);
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
