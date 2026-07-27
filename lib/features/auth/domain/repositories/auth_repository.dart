import '../entities/auth_session.dart';

abstract interface class AuthRepository {
  Future<AuthSession> signIn({required String email, required String password});
  Future<AuthSession> signUp({
    required String name,
    required String email,
    required String password,
  });
  Future<void> requestPasswordReset({required String email});
  Future<void> requestPhoneCode({required String phoneNumber});
  Future<AuthSession> signInWithPhone({
    required String phoneNumber,
    required String code,
  });

  /// Exchanges a rotating refresh token for a new session. Implementations must
  /// revoke the token family on detected reuse.
  Future<AuthSession> refreshSession({required String refreshToken});

  /// Best-effort server revocation of the current refresh-token family.
  Future<void> signOut({String? refreshToken});
}
