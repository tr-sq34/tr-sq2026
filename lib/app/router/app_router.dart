import 'package:flutter/material.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/community/application/community_feed_controller.dart';
import '../../features/community/application/community_comments_controller.dart';
import '../../features/community/application/profile_posts_controller.dart';
import '../../features/community/application/media_upload_controller.dart';
import '../../features/community/application/community_special_request_controller.dart';
import '../../features/events/application/events_controller.dart';
import '../../features/marketplace/application/marketplace_controller.dart';
import '../../features/profile/application/profile_controller.dart';
import '../../features/messaging/application/messaging_controller.dart';
import '../../features/messaging/presentation/screens/inbox_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/phone_login_screen.dart';
import '../../features/home/presentation/screens/main_layout_screen.dart';
import '../startup/startup_screen.dart';
import 'app_routes.dart';

class AppRouter {
  AppRouter({required this.authController, required this.communityController, required this.commentsController, required this.profilePostsController, required this.mediaUploadController, required this.specialRequestController, required this.eventsController, required this.marketplaceController, required this.profileController, required this.messagingController});

  final AuthController authController;
  final CommunityFeedController communityController;
  final CommunityCommentsController commentsController;
  final ProfilePostsController profilePostsController;
  final MediaUploadController mediaUploadController;
  final CommunitySpecialRequestController specialRequestController;
  final EventsController eventsController;
  final MarketplaceController marketplaceController;
  final ProfileController profileController;
  final MessagingController messagingController;

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
          builder: (context) => MainLayoutScreen(communityController: communityController, commentsController: commentsController, profilePostsController: profilePostsController, mediaUploadController: mediaUploadController, specialRequestController: specialRequestController, eventsController: eventsController, marketplaceController: marketplaceController, profileController: profileController, onSignOut: () async { await authController.signOut(); if (context.mounted) Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (_) => false); }),
        );
      case AppRoutes.inbox:
        return MaterialPageRoute<void>(settings: settings, builder: (_) => InboxScreen(controller: messagingController));
      case AppRoutes.register:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (context) => RegisterScreen(
            onSignUp: authController.signUp,
            onAuthenticated: () => Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.home, (_) => false),
          ),
        );
      case AppRoutes.forgotPassword:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => ForgotPasswordScreen(onRequestReset: authController.requestPasswordReset),
        );
      case AppRoutes.phoneLogin:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (context) => PhoneLoginScreen(
            onRequestCode: authController.requestPhoneCode,
            onVerifyCode: authController.signInWithPhone,
            onAuthenticated: () => Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.home, (_) => false),
          ),
        );
      case AppRoutes.login:
      default:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (context) => LoginScreen(
            onSignIn: authController.signIn,
            onAuthenticated: () => Navigator.of(context).pushReplacementNamed(AppRoutes.home),
            onForgotPassword: () => Navigator.of(context).pushNamed(AppRoutes.forgotPassword),
            onCreateAccount: () => Navigator.of(context).pushNamed(AppRoutes.register),
            onPhoneLogin: () => Navigator.of(context).pushNamed(AppRoutes.phoneLogin),
            onPasskeyLogin: authController.supportsPasskeys
                ? ({String? email}) => authController.signInWithPasskey(email: email)
                : null,
          ),
        );
    }
  }
}
