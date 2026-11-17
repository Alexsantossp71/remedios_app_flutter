import 'package:sqflite_common_ffi_web/src/sqflite_ffi_impl_web.dart'
    show SqfliteFfiHandlerWeb;
import 'package:sqflite_common_ffi_web/src/web/load_sqlite_web.dart'
    show SqfliteFfiWebContextExt;
import 'package:sqlite3/common.dart';
import 'package:sqlite3/wasm.dart';

/// sqflite Web handler that opens every persistent database through the
/// SQLite3MC VFS wrapper instead of the underlying plaintext VFS.
class Sqlite3McSqfliteHandler extends SqfliteFfiHandlerWeb {
  Sqlite3McSqfliteHandler(super.context);

  @override
  Future<CommonDatabase> openPlatform(Map argumentsMap) async {
    final sqlite = context.wasmSqlite3;
    final fileSystem = context.fs;
    if (sqlite == null || fileSystem == null) {
      throw StateError('SQLite3MC Web context is not initialized.');
    }

    final path = argumentsMap['path'] as String;
    final readOnly = (argumentsMap['readOnly'] as bool?) ?? false;
    final mode = readOnly ? OpenMode.readOnly : OpenMode.readWriteCreate;
    final encryptedVfs = 'multipleciphers-${fileSystem.name}';

    return sqlite.open(path, mode: mode, vfs: encryptedVfs);
  }
}
