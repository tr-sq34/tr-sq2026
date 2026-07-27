import '../entities/auth_session.dart';

/// Server-side WebAuthn contract. Native code receives only the short-lived
/// public-key options and returns a signed public-key credential.
abstract interface class PasskeyRepository {
  Future<Map<String, dynamic>> registrationOptions();
  Future<AuthSession> verifyRegistration(Map<String, dynamic> credential);

  Future<Map<String, dynamic>> authenticationOptions({String? email});
  Future<AuthSession> verifyAuthentication(Map<String, dynamic> credential);
}
