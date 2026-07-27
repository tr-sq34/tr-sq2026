import 'app_user.dart';

class AuthSession {
  const AuthSession({
    required this.user,
    required this.accessToken,
    this.refreshToken,
  });

  final AppUser user;
  final String accessToken;
  final String? refreshToken;
}
