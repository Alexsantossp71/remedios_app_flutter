import 'package:database_key_recovery_poc/testing/in_memory_database_key_store.dart';
import 'package:test/test.dart';

void main() {
  group('InMemoryDatabaseKeyStore test fake', () {
    test('reports missing key without generating one', () async {
      final store = InMemoryDatabaseKeyStore();

      expect(await store.readKey(), isNull);
      expect(await store.readKey(), isNull);
    });

    test('stores and returns a defensive copy', () async {
      final store = InMemoryDatabaseKeyStore();
      final expected = List<int>.generate(32, (index) => index);
      final input = List<int>.of(expected);
      await store.writeKey(input);
      input[0] = 255;

      final firstRead = await store.readKey();
      expect(firstRead, expected);
      firstRead![1] = 255;

      expect(await store.readKey(), expected);
    });

    test('rejects keys that are not exactly 32 bytes', () async {
      final store = InMemoryDatabaseKeyStore();

      await expectLater(store.writeKey([1, 2, 3]), throwsArgumentError);
      expect(await store.readKey(), isNull);
    });

    test('deletes the key explicitly', () async {
      final store = InMemoryDatabaseKeyStore();
      await store.writeKey(List<int>.filled(32, 7));

      await store.deleteKey();

      expect(await store.readKey(), isNull);
    });
  });
}
