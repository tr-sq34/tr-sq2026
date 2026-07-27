import '../../domain/entities/app_user.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/services/password_policy.dart';

/// Temporary implementation until the backend API is connected.
class MockAuthRepository implements AuthRepository {
  @override
  Future<AuthSession> signIn({
    required String email,
    required String password,
  }) async {
    if (email.trim().isEmpty || password.isEmpty) {
      throw const AuthException('Email and password are required.');
    }
    return AuthSession(
      user: AppUser(id: 'local-user', email: email.trim()),
      accessToken: 'development-access-token',
      refreshToken: 'development-refresh-token',
    );
  }

  @override
  Future<AuthSession> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    if (name.trim().length < 2 || !email.contains('@'))
      throw const AuthException('Geçerli bir ad ve e-posta girin.');
    if (PasswordPolicy.validate(password, email: email, name: name)
        case final error?)
      throw AuthException(error);
    return AuthSession(
      user: AppUser(id: 'local-user', email: email.trim()),
      accessToken: 'development-access-token',
      refreshToken: 'development-refresh-token',
    );
  }

  @override
  Future<void> requestPasswordReset({required String email}) async {
    if (!email.contains('@'))
      throw const AuthException('Enter a valid email address.');
  }

  @override
  Future<void> requestPhoneCode({required String phoneNumber}) async {
    if (phoneNumber.replaceAll(RegExp(r'\D'), '').length < 10) {
      throw const AuthException('Enter a valid phone number.');
    }
  }

  @override
  Future<AuthSession> signInWithPhone({
    required String phoneNumber,
    required String code,
  }) async {
    if (code != '123456')
      throw const AuthException('The verification code is incorrect.');
    return const AuthSession(
      user: AppUser(id: 'local-phone-user', email: 'phone-user@turksquare.app'),
      accessToken: 'development-access-token',
      refreshToken: 'development-refresh-token',
    );
  }

  @override
  Future<AuthSession> refreshSession({required String refreshToken}) async {
    if (refreshToken.isEmpty) throw const AuthException('Oturum yenilenemedi.');
    return const AuthSession(
      user: AppUser(id: 'local-user', email: 'member@turksquare.app'),
      accessToken: 'development-access-token',
      refreshToken: 'development-refresh-token',
    );
  }

  @override
  Future<void> signOut({String? refreshToken}) async {}
}

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
}
