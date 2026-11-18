/// Minimal key/value storage abstraction so the unlock state machine can be
/// tested on the Dart VM and is only bound to `window.localStorage` on web.
abstract interface class WebKeyValueStorage {
  String? getItem(String key);

  void setItem(String key, String value);

  void removeItem(String key);
}
