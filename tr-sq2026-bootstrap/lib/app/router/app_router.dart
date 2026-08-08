import 'package:flutter/material.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/phone_login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/home/presentation/screens/authenticated_home_screen.dart';
import '../startup/startup_screen.dart';
import 'app_routes.dart';

class AppRouter {
  AppRouter({required this.authController});

  final AuthController authController;

  Route<void> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.startup:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => StartupScreen(authController: authController),
        );
      case AppRoutes.home:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) =>
              AuthenticatedHomeScreen(authController: authController),
        );
      case AppRoutes.register:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (context) => RegisterScreen(
            onSignUp: authController.signUp,
            onAuthenticated: () => Navigator.of(
              context,
            ).pushNamedAndRemoveUntil(AppRoutes.home, (_) => false),
          ),
        );
      case AppRoutes.forgotPassword:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => ForgotPasswordScreen(
            onRequestReset: authController.requestPasswordReset,
          ),
        );
      case AppRoutes.phoneLogin:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (context) => PhoneLoginScreen(
            onRequestCode: authController.requestPhoneCode,
            onVerifyCode: authController.signInWithPhone,
            onAuthenticated: () => Navigator.of(
              context,
            ).pushNamedAndRemoveUntil(AppRoutes.home, (_) => false),
          ),
        );
      case AppRoutes.login:
      default:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (context) => LoginScreen(
            onSignIn: authController.signIn,
            onAuthenticated: () =>
                Navigator.of(context).pushReplacementNamed(AppRoutes.home),
            onForgotPassword: () =>
                Navigator.of(context).pushNamed(AppRoutes.forgotPassword),
            onCreateAccount: () =>
                Navigator.of(context).pushNamed(AppRoutes.register),
            onPhoneLogin: () =>
                Navigator.of(context).pushNamed(AppRoutes.phoneLogin),
            onPasskeyLogin: authController.supportsPasskeys
                ? ({String? email}) =>
                      authController.signInWithPasskey(email: email)
                : null,
          ),
        );
    }
  }
}
