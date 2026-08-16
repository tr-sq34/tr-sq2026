import 'package:flutter/foundation.dart';

import '../../../core/storage/session_store.dart';
import '../../../core/storage/token_store.dart';
import '../domain/entities/auth_session.dart';
import '../domain/entities/app_user.dart';
import '../domain/entities/onboarding_draft.dart';
import '../domain/entities/onboarding_profile.dart';
import '../domain/repositories/auth_repository.dart';
import '../domain/services/passkey_service.dart';

enum AuthStatus {
  initializing,
  unauthenticated,
  loading,
  authenticated,
  failure,
}

class AuthController extends ChangeNotifier {
  AuthController({
    required AuthRepository repository,
    required SessionStore sessionStore,
    required TokenStore tokenStore,
    PasskeyService? passkeyService,
  }) : _repository = repository,
       _sessionStore = sessionStore,
       _tokenStore = tokenStore,
       _passkeyService = passkeyService;

  final AuthRepository _repository;
  final SessionStore _sessionStore;
  final TokenStore _tokenStore;
  final PasskeyService? _passkeyService;
  AuthStatus _status = AuthStatus.initializing;
  AppUser? _user;
  OnboardingProfile? _onboarding;
  bool _onboardingUnknown = false;
  String? _errorMessage;

  AuthStatus get status => _status;
  AppUser? get user => _user;
  OnboardingProfile? get onboarding => _onboarding;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated =>
      _status == AuthStatus.authenticated && _user != null;
  bool get supportsPasskeys => _passkeyService != null;

  Future<bool> checkEmailStatus(String email) =>
      _repository.checkEmailStatus(email: email);

  Future<OnboardingProfile> getOnboarding() async {
    try {
      final profile = await _repository.getOnboarding();
      _onboarding = profile;
      _onboardingUnknown = false;
      return profile;
    } catch (_) {
      // Okunamadı ile "tamamlanmamış" aynı şey değil. Bayrak burada
      // kaldırılıyor ki her çağıran aynı cevabı görsün; hata yine de
      // yukarı çıkıyor, çünkü kimi çağıran bunu ekranda söylemek istiyor.
      _onboardingUnknown = true;
      rethrow;
    }
  }

  Future<void> saveOnboarding(OnboardingDraft draft) async {
    await _repository.saveOnboarding(draft);
    _onboarding = OnboardingProfile(
      completed: true,
      city: draft.city,
      countryCode: draft.countryCode,
      regionCode: draft.regionCode,
      interests: draft.interests,
      primaryIntent: draft.primaryIntent,
      bornInUs: draft.bornInUs,
      arrivedMonth: draft.arrivedMonth,
      arrivedYear: draft.arrivedYear,
      originCountry: draft.originCountry,
      originCity: draft.originCity,
    );
    _onboardingUnknown = false;
    notifyListeners();
  }

  /// Where a freshly authenticated member should land: onboarding only while it
  /// has not been completed. `_authenticate` already fetched the profile, so
  /// this needs no extra round trip.
  bool get needsOnboarding => !(_onboarding?.completed ?? false);

  /// Kurulumun bitip bitmediği okunamadı.
  ///
  /// Ölçülemeyen bir şey "tamamlanmamış" değildir. Sunucu bir an cevap
  /// vermediğinde [needsOnboarding] `true` döner ve bu, kurulumunu bir yıl önce
  /// bitirmiş bir üyeyi sihirbaza geri gönderiyordu — şehrini, geliş tarihini,
  /// ilgi alanlarını baştan yazdırıp gerçek profilinin üstüne kaydederek.
  /// O yüzden "bilmiyoruz" ayrı bir cevap ve yönlendirme buna bakıyor.
  bool get onboardingUnknown => _onboardingUnknown;

  Future<void> restoreSession() async {
    _status = AuthStatus.initializing;
    notifyListeners();
    final storedUser = await _sessionStore.readUser();
    final refreshToken = await _tokenStore.readRefreshToken();
    if (storedUser == null || refreshToken == null || refreshToken.isEmpty) {
      _user = null;
      _status = AuthStatus.unauthenticated;
    } else {
      try {
        final session = await _repository.refreshSession(
          refreshToken: refreshToken,
        );
        _user = session.user;
        await _sessionStore.saveUser(session.user);
        await _tokenStore.save(
          accessToken: session.accessToken,
          refreshToken: session.refreshToken ?? refreshToken,
        );
        _status = AuthStatus.authenticated;
        // Profil okunamazsa oturum yine de geçerli; nereye gidileceğine
        // [onboardingUnknown] karar veriyor.
        try {
          await getOnboarding();
        } catch (_) {}
      } catch (_) {
        await _sessionStore.clear();
        await _tokenStore.clear();
        _user = null;
        _status = AuthStatus.unauthenticated;
      }
    }
    notifyListeners();
  }

  Future<void> signIn(String email, String password) async {
    return _authenticate(
      () => _repository.signIn(email: email, password: password),
    );
  }

  Future<void> signUp(String name, String email, String password) async {
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();
    try {
      await _repository.signUp(name: name, email: email, password: password);
      _status = AuthStatus.unauthenticated;
    } catch (error) {
      _status = AuthStatus.failure;
      _errorMessage = error.toString().replaceFirst('Exception: ', '');
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> confirmEmailVerification(String email, String code) =>
      _repository.confirmEmailVerification(email: email, code: code);

  Future<void> resendEmailVerification(String email) =>
      _repository.resendEmailVerification(email: email);

  Future<void> signInWithPhone(String phoneNumber, String code) async {
    return _authenticate(
      () => _repository.signInWithPhone(phoneNumber: phoneNumber, code: code),
    );
  }

  Future<void> signInWithPasskey({String? email}) async {
    final service = _passkeyService;
    if (service == null) {
      throw StateError(
        'Passkey girişi bu uygulama yapılandırmasında etkin değil.',
      );
    }
    return _authenticate(() => service.authenticate(email: email));
  }

  Future<void> registerPasskey() async {
    final service = _passkeyService;
    if (service == null) {
      throw StateError(
        'Passkey kaydı bu uygulama yapılandırmasında etkin değil.',
      );
    }
    return _authenticate(service.register);
  }

  Future<void> requestPasswordReset(String email) {
    return _repository.requestPasswordReset(email: email);
  }

  Future<String> verifyPasswordResetCode(String email, String code) {
    return _repository.verifyPasswordResetCode(email: email, code: code);
  }

  Future<void> confirmPasswordReset(String ticket, String password) {
    return _repository.confirmPasswordReset(
      ticket: ticket,
      password: password,
    );
  }

  Future<void> requestPhoneCode(String phoneNumber) {
    return _repository.requestPhoneCode(phoneNumber: phoneNumber);
  }

  Future<void> _authenticate(Future<AuthSession> Function() action) async {
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();
    try {
      final session = await action();
      _user = session.user;
      await _sessionStore.saveUser(session.user);
      await _tokenStore.save(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
      );
      _status = AuthStatus.authenticated;
      // Aynısı taze girişte de geçerli: giriş başarılı oldu, okunamayan tek
      // şey kurulumun bitip bitmediği.
      try {
        await getOnboarding();
      } catch (_) {}
    } catch (error) {
      _status = AuthStatus.failure;
      _errorMessage = error.toString().replaceFirst('Exception: ', '');
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    final refreshToken = await _tokenStore.readRefreshToken();
    try {
      await _repository.signOut(refreshToken: refreshToken);
    } catch (_) {
      // Local revocation must not depend on network availability. The refresh
      // token will still expire server-side; a queued revocation can be added
      // when the product introduces offline session management.
    } finally {
      await expireSession();
    }
  }

  /// Hesabı dondurur. Sunucu bütün oturumları iptal ettiği için buradaki jeton
  /// da artık geçersiz: yerel kopyayı temizlemezsek uygulama, hiçbir isteği
  /// kabul edilmeyen bir oturumla açık kalırdı.
  Future<void> freezeAccount() async {
    await _repository.freezeAccount();
    await expireSession();
  }

  /// Hesabın silinmesini ister. Dönen tarih, vazgeçme süresinin son günü -
  /// o güne kadar tekrar giriş yapmak talebi geri alıyor.
  Future<DateTime> requestAccountDeletion(String password) async {
    final purgeAt = await _repository.requestAccountDeletion(
      password: password,
    );
    await expireSession();
    return purgeAt;
  }

  /// Used after a failed refresh. It intentionally makes no network call: the
  /// server may be unavailable and local credentials must still be removed.
  Future<void> expireSession() async {
    await _sessionStore.clear();
    await _tokenStore.clear();
    _user = null;
    _onboarding = null;
    _onboardingUnknown = false;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }
}
