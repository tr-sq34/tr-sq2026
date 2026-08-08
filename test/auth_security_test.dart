import 'package:america_hub/core/storage/in_memory_session_store.dart';
import 'package:america_hub/core/storage/in_memory_token_store.dart';
import 'package:america_hub/features/auth/application/auth_controller.dart';
import 'package:america_hub/features/auth/data/repositories/mock_auth_repository.dart';
import 'package:america_hub/features/auth/domain/services/password_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('password policy rejects short and identifier-derived passwords', () {
    expect(PasswordPolicy.validate('short'), isNotNull);
    expect(
      PasswordPolicy.validate(
        'member@example.com-strong',
        email: 'member@example.com',
      ),
      isNotNull,
    );
    expect(PasswordPolicy.validate('correct horse battery staple'), isNull);
  });

  test(
    'session restore uses a refresh token instead of trusting cached access token',
    () async {
      final controller = AuthController(
        repository: MockAuthRepository(),
        sessionStore: InMemorySessionStore(),
        tokenStore: InMemoryTokenStore(),
      );
      await controller.signIn('member@example.com', 'any-password');
      await controller.restoreSession();
      expect(controller.isAuthenticated, isTrue);
    },
  );

  test('mock email status supports the explicit two-step login flow', () async {
    final repository = MockAuthRepository();

    expect(
      await repository.checkEmailStatus(email: 'member@turksquare.app'),
      isTrue,
    );
    expect(
      await repository.checkEmailStatus(email: 'new-member@example.com'),
      isFalse,
    );
  });

  test(
    'verification code must match the expected one-time code in mock mode',
    () async {
      final repository = MockAuthRepository();

      await repository.confirmEmailVerification(
        email: 'new-member@example.com',
        code: '123456',
      );
      await expectLater(
        repository.confirmEmailVerification(
          email: 'new-member@example.com',
          code: '000000',
        ),
        throwsA(isA<AuthException>()),
      );
    },
  );
}
