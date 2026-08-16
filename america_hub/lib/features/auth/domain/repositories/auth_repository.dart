import '../entities/auth_session.dart';
import '../entities/onboarding_draft.dart';
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
  /// Asks for a six-digit reset code. Always succeeds for a well-formed
  /// address: the server refuses to reveal whether an account exists.
  Future<void> requestPasswordReset({required String email});

  /// Trades the emailed code for a single-use ticket. The code is spent by this
  /// call either way, so a wrong entry means asking for a new one.
  Future<String> verifyPasswordResetCode({
    required String email,
    required String code,
  });

  /// Sets the new password. The ticket is consumed here, and every existing
  /// session on the account is revoked server-side.
  Future<void> confirmPasswordReset({
    required String ticket,
    required String password,
  });
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
  Future<void> saveOnboarding(OnboardingDraft draft);

  /// Hesabı dondurur. Paylaşımlar, mesajlar ve arkadaşlıklar silinmiyor;
  /// yalnızca hesap kapanıyor ve oturumlar kesiliyor. Geri açmanın yolu tekrar
  /// giriş yapmak - bu yüzden şifre sorulmuyor.
  Future<void> freezeAccount();

  /// Hesabın silinmesini ister. Şifre burada tekrar soruluyor: geri alınamayan
  /// bir kararı, açık kalmış bir telefonu eline geçiren biri veremesin.
  /// Dönen tarih, vazgeçme süresinin bittiği an.
  Future<DateTime> requestAccountDeletion({required String password});
}
