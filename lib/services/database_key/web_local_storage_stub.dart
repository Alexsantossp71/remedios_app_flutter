import 'web_key_storage.dart';

/// VM/Android stub: localStorage only exists in browsers. Tests inject their
/// own [WebKeyValueStorage] implementation instead.
class LocalStorageKeyValueStorage implements WebKeyValueStorage {
  const LocalStorageKeyValueStorage();

  @override
  String? getItem(String key) {
    throw UnsupportedError('localStorage is only available on web builds.');
  }

  @override
  void setItem(String key, String value) {
    throw UnsupportedError('localStorage is only available on web builds.');
  }

  @override
  void removeItem(String key) {
    throw UnsupportedError('localStorage is only available on web builds.');
  }
}
