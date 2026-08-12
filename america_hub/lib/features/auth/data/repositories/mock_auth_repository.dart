import 'dart:convert';

import '../../../../core/cache/cache_store.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/onboarding_draft.dart';
import '../../domain/entities/onboarding_profile.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/services/password_policy.dart';

/// Temporary implementation until the backend API is connected.
///
/// It keeps one rule above all others: it never answers for a member it was
/// not told about. Whatever someone types into sign-up and the setup steps is
/// what comes back out — the demo fixture below belongs to exactly one address
/// and is never lent to anybody else.
class MockAuthRepository implements AuthRepository {
  /// [cacheStore] is where registrations and setup answers survive a restart.
  /// It defaults to memory so tests and widget previews can build one with no
  /// arguments; `main.dart` passes the shared `SharedPreferences` store.
  MockAuthRepository({CacheStore? cacheStore})
    : _store = cacheStore ?? MemoryCacheStore();

  final CacheStore _store;

  /// The account a reviewer signs straight into: verified, already onboarded
  /// and living in Paterson, so a cold emulator lands on the shell instead of
  /// the three setup steps.
  static const demoEmail = 'demo@turksquare.app';
  static const demoPassword = 'Gurbet2026!';
  static const demoName = 'Alican Argınç';

  /// `member@turksquare.app` stays the *un*-onboarded fixture: it exists, so
  /// the login screen asks for a password, and then it walks the setup flow.
  static const _knownEmails = {demoEmail, 'member@turksquare.app'};

  static const _sessionKey = 'mock_auth.session';
  static String _accountKey(String email) => 'mock_auth.account.$email';
  static String _onboardingKey(String email) => 'mock_auth.onboarding.$email';

  /// The address of whoever is signed in, normalised. Null before the first
  /// sign-in of the process; [_restoreSession] fills it from disk.
  String? _email;
  String? _displayName;

  /// Who the mock is answering for right now. `MockProfileRepository` reads
  /// these instead of inventing a person of its own.
  String? get currentEmail => _email;
  String? get currentDisplayName => _displayName;
  String? get currentUserId => _email == null ? null : _userIdFor(_email!);

  /// Same id the session hands the rest of the app, so the profile and the
  /// signed-in user are never two different people.
  static String _userIdFor(String email) =>
      email == demoEmail ? 'local-user' : 'local-$email';

  static String _normalise(String email) => email.trim().toLowerCase();

  @override
  Future<bool> checkEmailStatus({required String email}) async {
    if (!email.contains('@')) {
      throw const AuthException('Geçerli bir e-posta girin.');
    }
    final normalised = _normalise(email);
    if (_knownEmails.contains(normalised)) return true;
    // Someone who registered on this device earlier is an existing account too,
    // otherwise signing out and back in would fork into a second identity.
    return await _store.read(_accountKey(normalised)) != null;
  }

  @override
  Future<AuthSession> signIn({
    required String email,
    required String password,
  }) async {
    if (email.trim().isEmpty || password.isEmpty) {
      throw const AuthException('Email and password are required.');
    }
    final normalised = _normalise(email);
    _email = normalised;
    _displayName = normalised == demoEmail
        ? demoName
        : await _store.read(_accountKey(normalised));
    await _store.write(_sessionKey, normalised);
    return _sessionFor(normalised);
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
    final normalised = _normalise(email);
    _email = normalised;
    _displayName = name.trim();
    // A brand new registration still walks the setup steps, which is half of
    // what there is to review — and it starts with no onboarding answers, so
    // it gets none of the demo account's city or origin.
    await _store.write(_accountKey(normalised), _displayName!);
    await _store.remove(_onboardingKey(normalised));
    await _store.write(_sessionKey, normalised);
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
    const phoneEmail = 'phone-user@turksquare.app';
    _email = phoneEmail;
    _displayName = await _store.read(_accountKey(phoneEmail));
    await _store.write(_sessionKey, phoneEmail);
    return _sessionFor(phoneEmail);
  }

  @override
  Future<AuthSession> refreshSession({required String refreshToken}) async {
    if (refreshToken.isEmpty) throw const AuthException('Oturum yenilenemedi.');
    final restored = await _restoreSession();
    if (restored == null) {
      // No account was ever created on this device, so there is nobody to come
      // back as. Falling back to the demo here is what used to hand every cold
      // start somebody else's name and city.
      throw const AuthException('Oturum yenilenemedi.');
    }
    return _sessionFor(restored);
  }

  @override
  Future<void> signOut({String? refreshToken}) async {
    _email = null;
    _displayName = null;
    // The account and its answers stay on disk: signing back in must land on
    // the same person, not on a blank setup flow.
    await _store.remove(_sessionKey);
  }

  @override
  Future<OnboardingProfile> getOnboarding() async {
    final email = _email ?? await _restoreSession();
    if (email == null) return const OnboardingProfile(completed: false);
    if (await _store.read(_onboardingKey(email)) case final raw?) {
      return _decodeOnboarding(raw);
    }
    return email == demoEmail ? _demoOnboarding : const OnboardingProfile(completed: false);
  }

  @override
  Future<void> saveOnboarding(OnboardingDraft draft) async {
    final email = _email ?? await _restoreSession();
    if (email == null) {
      throw const AuthException('Oturum bulunamadı.');
    }
    await _store.write(_onboardingKey(email), jsonEncode(_encodeDraft(draft)));
  }

  /// Reads the last signed-in address back off disk and reinstates it as the
  /// current session. Returns null when this device has never had one.
  Future<String?> _restoreSession() async {
    if (_email != null) return _email;
    final email = await _store.read(_sessionKey);
    if (email == null) return null;
    _email = email;
    _displayName = email == demoEmail
        ? demoName
        : await _store.read(_accountKey(email));
    return email;
  }

  AuthSession _sessionFor(String email) => AuthSession(
    user: AppUser(
      id: _userIdFor(email),
      email: email,
      displayName: _displayName,
    ),
    accessToken: 'development-access-token',
    refreshToken: 'development-refresh-token',
  );

  static const _demoOnboarding = OnboardingProfile(
    completed: true,
    city: 'Paterson',
    countryCode: 'US',
    regionCode: 'NJ',
    interests: ['yemek', 'futbol', 'gocmenlik'],
    primaryIntent: 'newcomer',
    originCountry: 'TR',
    originCity: 'İzmir',
    arrivedMonth: 8,
    arrivedYear: 2019,
  );

  static Map<String, dynamic> _encodeDraft(OnboardingDraft draft) => {
    'city': draft.city,
    'countryCode': draft.countryCode,
    'regionCode': draft.regionCode,
    'interests': draft.interests,
    'primaryIntent': draft.primaryIntent,
    'bornInUs': draft.bornInUs,
    'arrivedMonth': draft.arrivedMonth,
    'arrivedYear': draft.arrivedYear,
    'originCountry': draft.originCountry,
    'originCity': draft.originCity,
  };

  static OnboardingProfile _decodeOnboarding(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return OnboardingProfile(
      completed: true,
      city: json['city'] as String?,
      countryCode: json['countryCode'] as String?,
      regionCode: json['regionCode'] as String?,
      interests: (json['interests'] as List<dynamic>? ?? const [])
          .cast<String>(),
      primaryIntent: json['primaryIntent'] as String?,
      bornInUs: json['bornInUs'] as bool? ?? false,
      arrivedMonth: json['arrivedMonth'] as int?,
      arrivedYear: json['arrivedYear'] as int?,
      originCountry: json['originCountry'] as String?,
      originCity: json['originCity'] as String?,
    );
  }
}

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
}
