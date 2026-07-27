import '../entities/auth_session.dart';

abstract interface class PasskeyService {
  Future<AuthSession> authenticate({String? email});
  Future<AuthSession> register();
}
