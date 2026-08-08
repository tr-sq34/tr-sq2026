import '../entities/auth_session.dart';
import '../entities/onboarding_profile.dart';

abstract interface class AuthRepository {
  /// Returns whether an account exists for the given normalized email address.
  /// The backend rate-limits this lookup because it is used only for the
  /// explicit two-step account flow.
  Future<bool> checkEmailStatus({required String email});
  Future<AuthSession> signIn({required String email, required String password});
  Future<void> signUp({
    required String name,
    required String email,
    required String password,
  });
  Future<void> confirmEmailVerification({
    required String email,
    required String code,
  });
  Future<void> resendEmailVerification({required String email});
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
  Future<OnboardingProfile> getOnboarding();
  Future<void> saveOnboarding({
    required String city,
    required String regionCode,
    required List<String> interests,
    required String primaryIntent,
  });
}
