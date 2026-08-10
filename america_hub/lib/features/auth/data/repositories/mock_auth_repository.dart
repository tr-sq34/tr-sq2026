import '../../domain/entities/app_user.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/onboarding_draft.dart';
import '../../domain/entities/onboarding_profile.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/services/password_policy.dart';

/// Temporary implementation until the backend API is connected.
class MockAuthRepository implements AuthRepository {
  /// The name given to [signUp], remembered so the rest of the mock session
  /// greets the member by it. Null until someone registers, which is the honest
  /// answer for a signed-in-from-cold mock: the UI then falls back to the
  /// address instead of a made-up name.
  String? _displayName;

  @override
  Future<bool> checkEmailStatus({required String email}) async {
    if (!email.contains('@')) {
      throw const AuthException('Geçerli bir e-posta girin.');
    }
    return email.trim().toLowerCase() == 'member@turksquare.app';
  }

  @override
  Future<AuthSession> signIn({
    required String email,
    required String password,
  }) async {
    if (email.trim().isEmpty || password.isEmpty) {
      throw const AuthException('Email and password are required.');
    }
    return AuthSession(
      user: AppUser(
        id: 'local-user',
        email: email.trim(),
        displayName: _displayName,
      ),
      accessToken: 'development-access-token',
      refreshToken: 'development-refresh-token',
    );
  }

  @override
  Future<void> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    if (name.trim().length < 2 || !email.contains('@')) {
      throw const AuthException('Geçerli bir ad ve e-posta girin.');
    }
    if (PasswordPolicy.validate(password, email: email, name: name)
        case final error?) {
      throw AuthException(error);
    }
    _displayName = name.trim();
  }

  @override
  Future<void> confirmEmailVerification({
    required String email,
    required String code,
  }) async {
    if (!email.contains('@') || code != '123456') {
      throw const AuthException('Kod geçersiz veya süresi dolmuş.');
    }
  }

  @override
  Future<void> resendEmailVerification({required String email}) async {
    if (!email.contains('@')) {
      throw const AuthException('Geçerli bir e-posta girin.');
    }
  }

  @override
  Future<void> requestPasswordReset({required String email}) async {
    if (!email.contains('@')) {
      throw const AuthException('Geçerli bir e-posta adresi girin.');
    }
  }

  @override
  Future<String> verifyPasswordResetCode({
    required String email,
    required String code,
  }) async {
    if (!email.contains('@') || code != '123456') {
      throw const AuthException('Kod geçersiz veya süresi dolmuş.');
    }
    return 'mock-password-reset-ticket';
  }

  @override
  Future<void> confirmPasswordReset({
    required String ticket,
    required String password,
  }) async {
    if (ticket != 'mock-password-reset-ticket') {
      throw const AuthException(
        'Sıfırlama oturumu geçersiz veya süresi dolmuş. Lütfen yeni kod isteyin.',
      );
    }
    // Mirrors the server: policy first, then the identical-password guard.
    if (PasswordPolicy.validate(password) case final error?) {
      throw AuthException(error);
    }
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
    if (code != '123456') {
      throw const AuthException('The verification code is incorrect.');
    }
    return AuthSession(
      user: AppUser(
        id: 'local-phone-user',
        email: 'phone-user@turksquare.app',
        displayName: _displayName,
      ),
      accessToken: 'development-access-token',
      refreshToken: 'development-refresh-token',
    );
  }

  @override
  Future<AuthSession> refreshSession({required String refreshToken}) async {
    if (refreshToken.isEmpty) throw const AuthException('Oturum yenilenemedi.');
    return AuthSession(
      user: AppUser(
        id: 'local-user',
        email: 'member@turksquare.app',
        displayName: _displayName,
      ),
      accessToken: 'development-access-token',
      refreshToken: 'development-refresh-token',
    );
  }

  @override
  Future<void> signOut({String? refreshToken}) async {}

  @override
  Future<OnboardingProfile> getOnboarding() async =>
      const OnboardingProfile(completed: false);

  @override
  Future<void> saveOnboarding(OnboardingDraft draft) async {}
}

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
}
