import '../../features/auth/domain/entities/app_user.dart';
import 'session_store.dart';

/// Testler ve geçici geliştirme akışları için bellek içi session store.
class InMemorySessionStore implements SessionStore {
  AppUser? _user;

  @override
  Future<void> clear() async => _user = null;

  @override
  Future<AppUser?> readUser() async => _user;

  @override
  Future<void> saveUser(AppUser user) async => _user = user;
}
