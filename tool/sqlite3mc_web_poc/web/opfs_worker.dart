import 'dart:js_interop';

import 'package:sqlite3/common.dart';
import 'package:sqlite3/wasm.dart';

const _testKey = 'only-a-public-fictional-browser-poc-key';
const _wrongKey = 'deliberately-wrong-test-key';
const _storageDirectory = 'sqlite3mc-browser-poc';

@JS('self.onmessage')
external set _onMessage(JSFunction callback);

@JS('self.postMessage')
external void _postMessage(JSAny? message);

@JS()
extension type _MessageEvent(JSObject _) implements JSObject {
  external JSAny? get data;
}

void main() {
  _onMessage = ((JSAny? rawEvent) {
    final command = (_MessageEvent(rawEvent as JSObject).data as JSString).toDart;
    _run(command).then(
      (result) => _postMessage(result.toJS),
      onError: (Object error, StackTrace stack) =>
          _postMessage('FAIL: $error\n$stack'.toJS),
    );
  }).toJS;
}

Future<String> _run(String command) async {
  final sqlite = await WasmSqlite3.loadFromUrlString('sqlite3mc.wasm');
  final fileSystem =
      await SimpleOpfsFileSystem.loadFromStorage(_storageDirectory);
  sqlite.registerVirtualFileSystem(fileSystem);
  final encryptedVfs = 'multipleciphers-${fileSystem.name}';

  CommonDatabase? db;
  try {
    if (command == 'write') {
      db = sqlite.open('/database', vfs: encryptedVfs);
      // PRAGMA key must be the first SQL statement on this connection.
      db.execute("PRAGMA key = '$_testKey'");
      db.execute('CREATE TABLE IF NOT EXISTS poc_records '
          '(id INTEGER PRIMARY KEY, value TEXT NOT NULL)');
      db.execute(
        "INSERT OR REPLACE INTO poc_records(id, value) VALUES "
        "(1, 'persisted encrypted OPFS record')",
      );
      db.close();
      db = null;
      return 'PASS: encrypted record written to OPFS';
    }

    if (command == 'verify') {
      db = sqlite.open('/database', vfs: encryptedVfs);
      db.execute("PRAGMA key = '$_testKey'");
      final rows = db.select('SELECT value FROM poc_records WHERE id = 1');
      if (rows.length != 1 ||
          rows.single['value'] != 'persisted encrypted OPFS record') {
        throw StateError('Encrypted record was not recovered after worker restart.');
      }
      db.close();
      db = null;
      return 'PASS: encrypted OPFS record recovered in a fresh worker';
    }

    if (command == 'wrong-key') {
      db = sqlite.open('/database', vfs: encryptedVfs);
      var rejected = false;
      try {
        db.execute("PRAGMA key = '$_wrongKey'");
        db.select('SELECT value FROM poc_records');
      } catch (_) {
        rejected = true;
      }
      db.close();
      db = null;
      if (!rejected) {
        throw StateError('SQLite3MC accepted an incorrect key.');
      }
      return 'PASS: incorrect key rejected';
    }

    throw ArgumentError.value(command, 'command', 'Unknown worker command');
  } finally {
    db?.close();
    fileSystem.close();
  }
}
