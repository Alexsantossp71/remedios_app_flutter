import '../database_key_store.dart';

/// In-memory fake for unit tests only. It is not secure storage.
final class InMemoryDatabaseKeyStore implements DatabaseKeyStore {
  List<int>? _key;

  @override
  Future<List<int>?> readKey() async {
    final key = _key;
    return key == null ? null : List<int>.of(key);
  }

  @override
  Future<bool> createKeyIfAbsent(List<int> key) async {
    if (key.length != 32) {
      throw ArgumentError('Database key must contain exactly 32 bytes.');
    }
    if (_key != null) return false;
    _key = List<int>.of(key);
    return true;
  }

  @override
  Future<void> deleteKey() async {
    _key = null;
  }
}
