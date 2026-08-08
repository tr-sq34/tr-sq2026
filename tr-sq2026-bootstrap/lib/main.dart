import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/network/api_client.dart';
import 'core/storage/session_store.dart';
import 'core/storage/token_store.dart';
import 'features/auth/application/auth_controller.dart';
import 'features/auth/data/repositories/api_auth_repository.dart';
import 'features/auth/data/repositories/mock_auth_repository.dart';
import 'features/auth/data/services/native_passkey_service.dart';
import 'features/auth/domain/repositories/auth_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final sessionStore = await SharedPreferencesSessionStore.create();
  final tokenStore = SecureTokenStore();
  // Production must never silently fall back to a local fake identity service.
  // Developers can opt into it with --dart-define=USE_MOCK_SERVICES=true.
  const useMockServices = bool.fromEnvironment(
    'USE_MOCK_SERVICES',
    defaultValue: false,
  );

  late final AuthController authController;
  final apiClient = ApiClient(
    tokenStore: tokenStore,
    onSessionExpired: () => authController.expireSession(),
  );
  final AuthRepository authRepository = useMockServices
      ? MockAuthRepository()
      : ApiAuthRepository(client: apiClient);
  final passkeyService = useMockServices
      ? null
      : NativePasskeyService(repository: authRepository as ApiAuthRepository);
  authController = AuthController(
    repository: authRepository,
    sessionStore: sessionStore,
    tokenStore: tokenStore,
    passkeyService: passkeyService,
  );

  runApp(AmericaHubApp(authController: authController));
}
