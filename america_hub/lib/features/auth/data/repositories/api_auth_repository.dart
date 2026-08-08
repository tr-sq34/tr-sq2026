import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/onboarding_profile.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/passkey_repository.dart';

/// API contract for the production identity service. Password hashing, email
/// verification, rate limiting and refresh-token-family reuse detection are
/// server responsibilities and must never be delegated to this client.
class ApiAuthRepository implements AuthRepository, PasskeyRepository {
  ApiAuthRepository({required ApiClient client}) : _client = client;
  final ApiClient _client;

  @override
  Future<bool> checkEmailStatus({required String email}) async {
    final response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.authEmailStatus,
      data: {'email': email.trim()},
    );
    final body =
        response.data?['data'] as Map<String, dynamic>? ??
        response.data ??
        const {};
    return body['exists'] == true;
  }

  @override
  Future<AuthSession> signIn({
    required String email,
    required String password,
  }) => _authenticate(ApiEndpoints.authLogin, {
    'email': email.trim(),
    'password': password,
  });

  @override
  Future<void> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    await _client.post<void>(
      ApiEndpoints.authRegister,
      data: {'name': name.trim(), 'email': email.trim(), 'password': password},
    );
  }

  @override
  Future<void> confirmEmailVerification({
    required String email,
    required String code,
  }) => _client.post<void>(
    ApiEndpoints.authEmailVerificationConfirm,
    data: {'email': email.trim(), 'code': code},
  );

  @override
  Future<void> resendEmailVerification({required String email}) =>
      _client.post<void>(
        ApiEndpoints.authEmailVerificationResend,
        data: {'email': email.trim()},
      );

  @override
  Future<AuthSession> refreshSession({required String refreshToken}) =>
      _authenticate(ApiEndpoints.authRefresh, {'refreshToken': refreshToken});

  Future<AuthSession> _authenticate(
    String endpoint,
    Map<String, dynamic> payload,
  ) async {
    final response = await _client.post<Map<String, dynamic>>(
      endpoint,
      data: payload,
    );
    final body =
        response.data?['data'] as Map<String, dynamic>? ??
        response.data ??
        const {};
    final user = body['user'] as Map<String, dynamic>? ?? const {};
    final accessToken = body['accessToken'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw StateError('Kimlik doğrulama servisi geçersiz yanıt verdi.');
    }
    return AuthSession(
      user: AppUser(
        id: user['id'] as String? ?? '',
        email: user['email'] as String? ?? '',
      ),
      accessToken: accessToken,
      refreshToken: body['refreshToken'] as String?,
    );
  }

  /// Raw WebAuthn payloads are intentionally opaque to Dart. Native platform
  /// code obtains credentials; the server verifies challenge/origin/signature.
  @override
  Future<Map<String, dynamic>> registrationOptions() async =>
      (await _client.post<Map<String, dynamic>>(
            ApiEndpoints.authPasskeyRegistrationOptions,
          )).data?['data']
          as Map<String, dynamic>? ??
      const {};

  @override
  Future<AuthSession> verifyRegistration(Map<String, dynamic> credential) =>
      _authenticate(ApiEndpoints.authPasskeyRegistrationVerify, credential);

  @override
  Future<Map<String, dynamic>> authenticationOptions({String? email}) async =>
      (await _client.post<Map<String, dynamic>>(
            ApiEndpoints.authPasskeyAuthenticationOptions,
            data: {if (email != null) 'email': email.trim()},
          )).data?['data']
          as Map<String, dynamic>? ??
      const {};

  @override
  Future<AuthSession> verifyAuthentication(Map<String, dynamic> credential) =>
      _authenticate(ApiEndpoints.authPasskeyAuthenticationVerify, credential);

  @override
  Future<void> requestPasswordReset({required String email}) async =>
      _client.post<void>(
        '/auth/password-reset/request',
        data: {'email': email.trim()},
      );
  @override
  Future<void> requestPhoneCode({required String phoneNumber}) async => _client
      .post<void>('/auth/phone/request', data: {'phoneNumber': phoneNumber});
  @override
  Future<AuthSession> signInWithPhone({
    required String phoneNumber,
    required String code,
  }) => _authenticate('/auth/phone/verify', {
    'phoneNumber': phoneNumber,
    'code': code,
  });
  @override
  Future<void> signOut({String? refreshToken}) async {
    if (refreshToken == null || refreshToken.isEmpty) return;
    await _client.post<void>(
      ApiEndpoints.authLogout,
      data: {'refreshToken': refreshToken},
    );
  }

  @override
  Future<OnboardingProfile> getOnboarding() async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.authOnboarding,
    );
    final data =
        response.data?['data'] as Map<String, dynamic>? ??
        response.data ??
        const {};
    return OnboardingProfile(
      completed: data['completed'] == true,
      city: data['city'] as String?,
      regionCode: data['regionCode'] as String?,
      interests: (data['interests'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      primaryIntent: data['primaryIntent'] as String?,
    );
  }

  @override
  Future<void> saveOnboarding({
    required String city,
    required String regionCode,
    required List<String> interests,
    required String primaryIntent,
  }) => _client.put<void>(
    ApiEndpoints.authOnboarding,
    data: {
      'city': city.trim(),
      'regionCode': regionCode,
      'interests': interests,
      'primaryIntent': primaryIntent,
    },
  );
}
