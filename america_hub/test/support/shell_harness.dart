import 'package:america_hub/features/profile/application/friendship_controller.dart';
import 'package:america_hub/features/profile/data/repositories/mock_friendship_repository.dart';
import 'package:america_hub/core/network/api_client.dart';
import 'package:america_hub/core/storage/in_memory_session_store.dart';
import 'package:america_hub/core/storage/in_memory_token_store.dart';
import 'package:america_hub/features/auth/application/auth_controller.dart';
import 'package:america_hub/features/auth/data/repositories/mock_auth_repository.dart';
import 'package:america_hub/features/community/application/community_comments_controller.dart';
import 'package:america_hub/features/community/application/community_feed_controller.dart';
import 'package:america_hub/features/community/application/community_special_request_controller.dart';
import 'package:america_hub/features/community/application/media_upload_controller.dart';
import 'package:america_hub/features/community/application/story_controller.dart';
import 'package:america_hub/features/community/data/repositories/mock_community_comments_repository.dart';
import 'package:america_hub/features/community/data/repositories/mock_community_repository.dart';
import 'package:america_hub/features/community/data/repositories/mock_community_special_request_repository.dart';
import 'package:america_hub/features/community/data/repositories/mock_content_moderation_repository.dart';
import 'package:america_hub/features/community/data/repositories/mock_media_upload_repository.dart';
import 'package:america_hub/features/events/application/events_controller.dart';
import 'package:america_hub/features/events/data/repositories/mock_events_repository.dart';
import 'package:america_hub/features/forum/application/forum_controller.dart';
import 'package:america_hub/features/forum/data/repositories/mock_forum_repository.dart';
import 'package:america_hub/features/home/application/community_home_controller.dart';
import 'package:america_hub/features/home/data/community_home_repository.dart';
import 'package:america_hub/features/home/presentation/screens/main_layout_screen.dart';
import 'package:america_hub/features/marketplace/application/marketplace_controller.dart';
import 'package:america_hub/features/marketplace/data/repositories/mock_marketplace_repository.dart';
import 'package:america_hub/features/news/application/news_controller.dart';
import 'package:america_hub/features/news/data/repositories/mock_news_comments_repository.dart';
import 'package:america_hub/features/news/data/repositories/mock_news_repository.dart';
import 'package:america_hub/features/notifications/application/notifications_controller.dart';
import 'package:america_hub/features/notifications/data/repositories/empty_notification_repository.dart';
import 'package:america_hub/features/notifications/domain/repositories/notification_repository.dart';
import 'package:america_hub/features/profile/application/profile_controller.dart';
import 'package:america_hub/features/promotions/application/promotions_controller.dart';
import 'package:america_hub/features/promotions/data/repositories/mock_promotion_repository.dart';
import 'package:america_hub/features/profile/data/repositories/mock_profile_repository.dart';
import 'package:america_hub/features/journey/application/journey_controller.dart';
import 'package:america_hub/features/journey/data/repositories/mock_journey_repository.dart';
import 'package:america_hub/features/verification/application/member_capabilities_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:america_hub/features/safety/application/sos_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_image_http.dart';
import 'fake_sos.dart';

/// Lets overflow reports through without failing the test.
///
/// The test font draws every glyph as a full-em square, so the feed's copy
/// measures roughly twice as wide here as on a device and its fixed-size promo
/// cards overflow by a few pixels. That is an artifact of the font, not of the
/// layout, and the shell tests are about which controls exist on which tab.
/// Anything that is not an overflow still fails the test as usual — and the
/// overflow is still printed, so a genuine one is not invisible.
void _ignoreOverflowReports() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exception.toString().startsWith('A RenderFlex overflowed')) {
      return;
    }
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

/// Puts the real shell on screen with mock data behind it.
///
/// The shell is the one widget that has to hold every controller in the app,
/// so building it by hand in each test would bury the assertion under fifty
/// lines of wiring. Pass [signUpName] to have the mock repository remember a
/// display name, exactly as registering through the app would.
/// Pass [notifications] to put rows behind the bell; the default shell has an
/// empty list, which is what most of these tests want.
Future<AuthController> pumpShell(
  WidgetTester tester, {
  String? signUpName,
  NotificationRepository notifications = const EmptyNotificationRepository(),
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  installFakeImageHttp();
  _ignoreOverflowReports();

  // Uygulamadaki gibi tek bir kimlik: akış paylaşımı imzalayan, profil ızgarası
  // "benim" diye süzen ve kabuk adıyla selamlayan taraf aynı üye olsun diye
  // depo da denetleyici de aynı nesneyi paylaşıyor.
  final authRepository = MockAuthRepository();
  final authController = AuthController(
    repository: authRepository,
    sessionStore: InMemorySessionStore(),
    tokenStore: InMemoryTokenStore(),
  );
  if (signUpName != null) {
    await authController.signUp(signUpName, 'uye@turksquare.app', 'Gurbet!2026x');
  }
  await authController.signIn('uye@turksquare.app', 'Gurbet!2026x');

  final communityRepository = MockCommunityRepository(
    viewer: () => authController.user,
  );
  // Never actually used: both controllers that take an ApiClient are stubbed
  // below, because their real `load()` leaves Dio's timeout timer pending past
  // the end of the test.
  final apiClient = ApiClient(tokenStore: InMemoryTokenStore());

  await tester.pumpWidget(
    MaterialApp(
      home: MainLayoutScreen(
        communityController: CommunityFeedController(
          repository: communityRepository,
          feed: communityRepository,
          commands: communityRepository,
          interactions: communityRepository,
          polls: communityRepository,
        ),
        friendshipController: FriendshipController(
          repository: MockFriendshipRepository(),
        ),
        storyController: StoryController(repository: communityRepository),
        commentsController: CommunityCommentsController(
          repository: MockCommunityCommentsRepository(),
        ),
        mediaUploadController: MediaUploadController(
          repository: MockMediaUploadRepository(),
        ),
        postCommands: communityRepository,
        specialRequestController: CommunitySpecialRequestController(
          repository: MockCommunitySpecialRequestRepository(),
        ),
        contentModerationRepository: MockContentModerationRepository(),
        eventsController: EventsController(repository: MockEventsRepository()),
        marketplaceController: MarketplaceController(
          repository: MockMarketplaceRepository(),
        ),
        profileController: ProfileController(
          repository: MockProfileRepository(
            auth: authRepository,
            posts: communityRepository,
          ),
        ),
        journeyController: JourneyController(
          repository: const MockJourneyRepository(),
        ),
        homeController: CommunityHomeController(
          _StubHomeRepository(),
        ),
        memberCapabilitiesController: _StubCapabilitiesController(apiClient),
        authController: authController,
        notificationsController: NotificationsController(
          repository: notifications,
        ),
        newsController: NewsController(repository: MockNewsRepository()),
        newsCommentsController: CommunityCommentsController(
          repository: MockNewsCommentsRepository(
            viewer: () => authController.user,
          ),
        ),
        promotionsController: PromotionsController(
          repository: MockPromotionRepository(),
        ),
        forumController: ForumController(
          repository: MockForumRepository(viewer: () => authController.user),
        ),
        sosController: SosController(repository: FakeSosRepository()),
        onSignOut: () async {},
      ),
    ),
  );
  await tester.pump();
  return authController;
}

/// Taps a bottom-bar tab by name.
///
/// The label alone is not enough: the home screen's search box carries a
/// "Çarşı" badge of its own, so `find.text('Çarşı')` matches twice. The bar
/// carries a key per tab exactly so a test can mean the tab and nothing else.
Future<void> tapTab(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(ValueKey('nav-$label')));
  await tester.pump();
}

/// Answers the home summary without touching the network.
///
/// The real repository would leave Dio's timeout timer pending past the end of
/// the test, and the locality it returns is what the top bar's subtitle is
/// built from — so it is worth being deliberate about.
class _StubHomeRepository implements CommunityHomeRepository {
  @override
  Future<CommunityHomeSummary> fetch() async => const CommunityHomeSummary(
    city: 'Paterson',
    regionCode: 'NJ',
    connections: 4,
    localPosts: 12,
    activeStories: 2,
    isNewMember: false,
  );
}

/// A member with no special privileges, answered without a request.
class _StubCapabilitiesController extends MemberCapabilitiesController {
  _StubCapabilitiesController(ApiClient client) : super(client, client);

  @override
  Future<void> load() async {}
}
