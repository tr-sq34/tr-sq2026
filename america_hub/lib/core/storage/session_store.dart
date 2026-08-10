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
  static const _displayNameKey = 'session.user_display_name';

  final SharedPreferences _preferences;

  static Future<SharedPreferencesSessionStore> create() async {
    return SharedPreferencesSessionStore(await SharedPreferences.getInstance());
  }

  @override
  Future<AppUser?> readUser() async {
    final id = _preferences.getString(_userIdKey);
    final email = _preferences.getString(_emailKey);
    if (id == null || email == null) return null;
    return AppUser(
      id: id,
      email: email,
      displayName: _preferences.getString(_displayNameKey),
    );
  }

  @override
  Future<void> saveUser(AppUser user) async {
    await _preferences.setString(_userIdKey, user.id);
    await _preferences.setString(_emailKey, user.email);
    // Removed rather than written empty when absent, so a stale name from a
    // previous account can never outlive it.
    final displayName = user.displayName?.trim();
    if (displayName == null || displayName.isEmpty) {
      await _preferences.remove(_displayNameKey);
    } else {
      await _preferences.setString(_displayNameKey, displayName);
    }
  }

  @override
  Future<void> clear() async {
    await _preferences.remove(_userIdKey);
    await _preferences.remove(_emailKey);
    await _preferences.remove(_displayNameKey);
  }
}
