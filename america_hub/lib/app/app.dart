import 'package:flutter/material.dart';

import '../features/auth/application/auth_controller.dart';
import '../features/community/application/community_feed_controller.dart';
import '../features/community/application/story_controller.dart';
import '../features/community/application/community_comments_controller.dart';
import '../features/community/application/media_upload_controller.dart';
import '../features/community/domain/repositories/community_repository.dart';
import '../features/community/application/community_special_request_controller.dart';
import '../features/events/application/events_controller.dart';
import '../features/marketplace/application/marketplace_controller.dart';
import '../features/profile/application/profile_controller.dart';
import '../features/journey/application/journey_controller.dart';
import '../features/messaging/application/messaging_controller.dart';
import '../features/messaging/domain/repositories/direct_message_repository.dart';
import '../features/community/domain/repositories/content_moderation_repository.dart';
import '../features/messaging/domain/repositories/message_moderation_repository.dart';
import '../features/home/application/community_home_controller.dart';
import '../features/news/application/news_controller.dart';
import '../features/notifications/application/notifications_controller.dart';
import '../features/promotions/application/promotions_controller.dart';
import '../features/verification/application/member_capabilities_controller.dart';
import 'router/app_router.dart';
import 'router/app_routes.dart';
import 'theme/app_theme.dart';

class AmericaHubApp extends StatelessWidget {
  const AmericaHubApp({
    super.key,
    required this.authController,
    required this.communityController,
    required this.storyController,
    required this.commentsController,
    required this.mediaUploadController,
    required this.postCommands,
    required this.specialRequestController,
    required this.eventsController,
    required this.marketplaceController,
    required this.profileController,
    required this.journeyController,
    required this.messagingController,
    required this.directMessageRepository,
    required this.messageModerationRepository,
    required this.contentModerationRepository,
    required this.communityHomeController,
    required this.memberCapabilitiesController,
    required this.notificationsController,
    required this.newsController,
    required this.newsCommentsController,
    required this.promotionsController,
  });

  final AuthController authController;
  final CommunityFeedController communityController;
  final StoryController storyController;
  final CommunityCommentsController commentsController;
  final MediaUploadController mediaUploadController;

  /// Deleting a post from the profile grid goes through the same commands the
  /// feed uses, so a post removed here disappears everywhere at once.
  final CommunityPostCommands postCommands;
  final CommunitySpecialRequestController specialRequestController;
  final EventsController eventsController;
  final MarketplaceController marketplaceController;
  final ProfileController profileController;
  final JourneyController journeyController;
  final MessagingController messagingController;

  /// A chat thread gets its own controller when it is opened, so what is held
  /// here is the repository behind it rather than a controller instance.
  final DirectMessageRepository directMessageRepository;

  /// Reporting and blocking, held here for the same reason: the thread that
  /// uses them does not exist until it is opened.
  final MessageModerationRepository messageModerationRepository;

  /// Reporting for feed content — posts, comments and stories. Held next to the
  /// messaging one because the widgets that use it are built per post, per
  /// comment and per story, far below this point.
  final ContentModerationRepository contentModerationRepository;
  final CommunityHomeController communityHomeController;
  final MemberCapabilitiesController memberCapabilitiesController;
  final NotificationsController notificationsController;
  final NewsController newsController;

  /// News comments use the feed's controller class against a different
  /// repository: the editor is shared, the threads are not.
  final CommunityCommentsController newsCommentsController;

  /// Sponsorlu Story yuvası ve öne çıkan kartlar; ana sayfa bunu okur.
  final PromotionsController promotionsController;

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
        storyController: storyController,
        commentsController: commentsController,
        mediaUploadController: mediaUploadController,
        postCommands: postCommands,
        specialRequestController: specialRequestController,
        eventsController: eventsController,
        marketplaceController: marketplaceController,
        profileController: profileController,
        journeyController: journeyController,
        messagingController: messagingController,
        directMessageRepository: directMessageRepository,
        messageModerationRepository: messageModerationRepository,
        contentModerationRepository: contentModerationRepository,
        communityHomeController: communityHomeController,
        memberCapabilitiesController: memberCapabilitiesController,
        notificationsController: notificationsController,
        newsController: newsController,
        newsCommentsController: newsCommentsController,
        promotionsController: promotionsController,
      ).onGenerateRoute,
    );
  }
}
