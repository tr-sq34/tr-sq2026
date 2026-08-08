import 'package:shared_preferences/shared_preferences.dart';

abstract interface class CacheStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

class SharedPreferencesCacheStore implements CacheStore {
  SharedPreferencesCacheStore(this._preferences);
  final SharedPreferences _preferences;

  static Future<SharedPreferencesCacheStore> create() async => SharedPreferencesCacheStore(await SharedPreferences.getInstance());

  @override
  Future<String?> read(String key) async => _preferences.getString(key);

  @override
  Future<void> remove(String key) async => _preferences.remove(key);

  @override
  Future<void> write(String key, String value) async => _preferences.setString(key, value);
}

class MemoryCacheStore implements CacheStore {
  final Map<String, String> _values = {};
  @override
  Future<String?> read(String key) async => _values[key];
  @override
  Future<void> remove(String key) async => _values.remove(key);
  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}
