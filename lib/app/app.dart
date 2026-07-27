import 'package:flutter/material.dart';

import '../features/auth/application/auth_controller.dart';
import '../features/community/application/community_feed_controller.dart';
import '../features/community/application/community_comments_controller.dart';
import '../features/community/application/profile_posts_controller.dart';
import '../features/community/application/media_upload_controller.dart';
import '../features/community/application/community_special_request_controller.dart';
import '../features/events/application/events_controller.dart';
import '../features/marketplace/application/marketplace_controller.dart';
import '../features/profile/application/profile_controller.dart';
import '../features/messaging/application/messaging_controller.dart';
import 'router/app_router.dart';
import 'router/app_routes.dart';
import 'theme/app_theme.dart';

class AmericaHubApp extends StatelessWidget {
  const AmericaHubApp({
    super.key,
    required this.authController,
    required this.communityController,
    required this.commentsController,
    required this.profilePostsController,
    required this.mediaUploadController,
    required this.specialRequestController,
    required this.eventsController,
    required this.marketplaceController,
    required this.profileController,
    required this.messagingController,
  });

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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TurkSquare',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      initialRoute: AppRoutes.startup,
      onGenerateRoute: AppRouter(
        authController: authController,
        communityController: communityController,
        commentsController: commentsController,
        profilePostsController: profilePostsController,
        mediaUploadController: mediaUploadController,
        specialRequestController: specialRequestController,
        eventsController: eventsController,
        marketplaceController: marketplaceController,
        profileController: profileController,
        messagingController: messagingController,
      ).onGenerateRoute,
    );
  }
}
