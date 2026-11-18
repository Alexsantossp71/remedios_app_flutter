import 'package:web/web.dart' as web;

import 'web_key_storage.dart';

/// `window.localStorage` binding (package:web, que já expõe tipos Dart).
///
/// This file is only compiled for web builds (conditional import from
/// `web_database_key_store.dart`).
class LocalStorageKeyValueStorage implements WebKeyValueStorage {
  const LocalStorageKeyValueStorage();

  @override
  String? getItem(String key) => web.window.localStorage.getItem(key);

  @override
  void setItem(String key, String value) {
    web.window.localStorage.setItem(key, value);
  }

  @override
  void removeItem(String key) {
    web.window.localStorage.removeItem(key);
  }
}
