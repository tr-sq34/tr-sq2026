import 'package:passkeys/authenticator.dart';
import 'package:passkeys/types.dart';

import '../../domain/entities/auth_session.dart';
import '../../domain/repositories/passkey_repository.dart';
import '../../domain/services/passkey_service.dart';

/// Bridges the server's WebAuthn JSON to Android Credential Manager / Apple
/// AuthenticationServices. It deliberately does not inspect or verify signed
/// credential data; verification is exclusively performed by the API.
class NativePasskeyService implements PasskeyService {
  NativePasskeyService({
    required PasskeyRepository repository,
    PasskeyAuthenticator? authenticator,
  }) : _repository = repository,
       _authenticator = authenticator ?? PasskeyAuthenticator();

  final PasskeyRepository _repository;
  final PasskeyAuthenticator _authenticator;

  @override
  Future<AuthSession> authenticate({String? email}) async {
    final options = await _repository.authenticationOptions(email: email);
    final assertion = await _authenticator.authenticate(
      AuthenticateRequestType.fromJson(
        Map<String, dynamic>.from(options),
        preferImmediatelyAvailableCredentials: false,
      ),
    );
    return _repository.verifyAuthentication(assertion.toJson());
  }

  @override
  Future<AuthSession> register() async {
    final options = await _repository.registrationOptions();
    final credential = await _authenticator.register(
      RegisterRequestType.fromJson(Map<String, dynamic>.from(options)),
    );
    return _repository.verifyRegistration(credential.toJson());
  }
}
