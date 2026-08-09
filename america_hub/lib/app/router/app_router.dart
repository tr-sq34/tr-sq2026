import 'package:flutter/material.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/community/application/community_feed_controller.dart';
import '../../features/community/application/story_controller.dart';
import '../../features/community/application/community_comments_controller.dart';
import '../../features/community/application/profile_posts_controller.dart';
import '../../features/community/application/media_upload_controller.dart';
import '../../features/community/application/community_special_request_controller.dart';
import '../../features/events/application/events_controller.dart';
import '../../features/marketplace/application/marketplace_controller.dart';
import '../../features/profile/application/profile_controller.dart';
import '../../features/messaging/application/direct_conversation_controller.dart';
import '../../features/messaging/application/messaging_controller.dart';
import '../../features/messaging/domain/repositories/direct_message_repository.dart';
import '../../features/community/domain/repositories/content_moderation_repository.dart';
import '../../features/messaging/domain/repositories/message_moderation_repository.dart';
import '../../features/messaging/presentation/screens/inbox_screen.dart';
import '../../features/home/application/community_home_controller.dart';
import '../../features/verification/application/member_capabilities_controller.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/phone_login_screen.dart';
import '../../features/auth/presentation/screens/email_verification_screen.dart';
import '../../features/auth/presentation/screens/onboarding_screen.dart';
import '../../features/home/presentation/screens/main_layout_screen.dart';
import '../startup/startup_screen.dart';
import 'app_routes.dart';

class AppRouter {
  AppRouter({
    required this.authController,
    required this.communityController,
    required this.storyController,
    required this.commentsController,
    required this.profilePostsController,
    required this.mediaUploadController,
    required this.specialRequestController,
    required this.eventsController,
    required this.marketplaceController,
    required this.profileController,
    required this.messagingController,
    required this.directMessageRepository,
    required this.messageModerationRepository,
    required this.contentModerationRepository,
    required this.communityHomeController,
    required this.memberCapabilitiesController,
  });

  final AuthController authController;
  final CommunityFeedController communityController;
  final StoryController storyController;
  final CommunityCommentsController commentsController;
  final ProfilePostsController profilePostsController;
  final MediaUploadController mediaUploadController;
  final CommunitySpecialRequestController specialRequestController;
  final EventsController eventsController;
  final MarketplaceController marketplaceController;
  final ProfileController profileController;
  final MessagingController messagingController;
  final DirectMessageRepository directMessageRepository;
  final MessageModerationRepository messageModerationRepository;
  final ContentModerationRepository contentModerationRepository;
  final CommunityHomeController communityHomeController;
  final MemberCapabilitiesController memberCapabilitiesController;

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
          builder: (context) => MainLayoutScreen(
            communityController: communityController,
            storyController: storyController,
            commentsController: commentsController,
            profilePostsController: profilePostsController,
            mediaUploadController: mediaUploadController,
            specialRequestController: specialRequestController,
            eventsController: eventsController,
            marketplaceController: marketplaceController,
            profileController: profileController,
            contentModerationRepository: contentModerationRepository,
            homeController: communityHomeController,
            memberCapabilitiesController: memberCapabilitiesController,
            authController: authController,
            onSignOut: () async {
              await authController.signOut();
              if (context.mounted) {
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
              }
            },
          ),
        );
      case AppRoutes.onboarding:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (context) => OnboardingScreen(
            onComplete: (city, regionCode, interests, intent) async {
              await authController.saveOnboarding(
                city: city,
                regionCode: regionCode,
                interests: interests,
                primaryIntent: intent,
              );
              if (context.mounted) {
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil(AppRoutes.home, (_) => false);
              }
            },
          ),
        );
      case AppRoutes.inbox:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => InboxScreen(
            controller: messagingController,
            // Read at open time, not at construction: the signed-in user is
            // only known once authentication has completed.
            createConversationController: (conversationId) =>
                DirectConversationController(
                  repository: directMessageRepository,
                  conversationId: conversationId,
                  viewerId: authController.user?.id ?? '',
                ),
            moderationRepository: messageModerationRepository,
          ),
        );
      case AppRoutes.register:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (context) => RegisterScreen(
            onSignUp: authController.signUp,
            onAuthenticated: () => Navigator.of(
              context,
            ).pushNamedAndRemoveUntil(AppRoutes.onboarding, (_) => false),
            initialEmail: settings.arguments as String?,
            onVerificationRequired: (email) =>
                Navigator.of(context).pushReplacementNamed(
                  AppRoutes.emailVerification,
                  arguments: email,
                ),
          ),
        );
      case AppRoutes.emailVerification:
        final email = settings.arguments as String? ?? '';
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (context) => EmailVerificationScreen(
            email: email,
            onConfirm: authController.confirmEmailVerification,
            onResend: authController.resendEmailVerification,
            onVerified: () => Navigator.of(context).pushNamedAndRemoveUntil(
              AppRoutes.login,
              (_) => false,
              arguments: email,
            ),
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
            ).pushNamedAndRemoveUntil(AppRoutes.onboarding, (_) => false),
          ),
        );
      case AppRoutes.login:
      default:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (context) => LoginScreen(
            onCheckEmailStatus: authController.checkEmailStatus,
            initialEmail: settings.arguments as String?,
            onRegisterWithEmail: (email) => Navigator.of(
              context,
            ).pushNamed(AppRoutes.register, arguments: email),
            onSignIn: authController.signIn,
            onAuthenticated: () => Navigator.of(
              context,
            ).pushReplacementNamed(AppRoutes.onboarding),
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
