import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/domain/entities/app_user.dart';

abstract interface class SessionStore {
  Future<AppUser?> readUser();
  Future<void> saveUser(AppUser user);
  Future<void> clear();
}

class SharedPreferencesSessionStore implements SessionStore {
  SharedPreferencesSessionStore(this._preferences);

  static const _userIdKey = 'session.user_id';
  static const _emailKey = 'session.user_email';

  final SharedPreferences _preferences;

  static Future<SharedPreferencesSessionStore> create() async {
    return SharedPreferencesSessionStore(await SharedPreferences.getInstance());
  }

  @override
  Future<AppUser?> readUser() async {
    final id = _preferences.getString(_userIdKey);
    final email = _preferences.getString(_emailKey);
    if (id == null || email == null) return null;
    return AppUser(id: id, email: email);
  }

  @override
  Future<void> saveUser(AppUser user) async {
    await _preferences.setString(_userIdKey, user.id);
    await _preferences.setString(_emailKey, user.email);
  }

  @override
  Future<void> clear() async {
    await _preferences.remove(_userIdKey);
    await _preferences.remove(_emailKey);
  }
}
