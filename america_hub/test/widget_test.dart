import 'package:america_hub/app/app.dart';
import 'package:america_hub/core/network/api_client.dart';
import 'package:america_hub/core/storage/in_memory_session_store.dart';
import 'package:america_hub/core/storage/in_memory_token_store.dart';
import 'package:america_hub/features/auth/application/auth_controller.dart';
import 'package:america_hub/features/auth/data/repositories/mock_auth_repository.dart';
import 'package:america_hub/features/community/application/community_feed_controller.dart';
import 'package:america_hub/features/community/application/community_comments_controller.dart';
import 'package:america_hub/features/community/application/profile_posts_controller.dart';
import 'package:america_hub/features/community/application/media_upload_controller.dart';
import 'package:america_hub/features/community/application/community_special_request_controller.dart';
import 'package:america_hub/features/community/application/story_controller.dart';
import 'package:america_hub/features/community/data/repositories/mock_community_repository.dart';
import 'package:america_hub/features/community/data/repositories/mock_community_comments_repository.dart';
import 'package:america_hub/features/community/data/repositories/mock_media_upload_repository.dart';
import 'package:america_hub/features/community/data/repositories/mock_community_special_request_repository.dart';
import 'package:america_hub/features/community/data/repositories/mock_content_moderation_repository.dart';
import 'package:america_hub/features/events/application/events_controller.dart';
import 'package:america_hub/features/home/application/community_home_controller.dart';
import 'package:america_hub/features/home/data/community_home_repository.dart';
import 'package:america_hub/features/events/data/repositories/mock_events_repository.dart';
import 'package:america_hub/features/marketplace/application/marketplace_controller.dart';
import 'package:america_hub/features/marketplace/data/repositories/mock_marketplace_repository.dart';
import 'package:america_hub/features/messaging/application/messaging_controller.dart';
import 'package:america_hub/features/messaging/data/repositories/mock_direct_message_repository.dart';
import 'package:america_hub/features/messaging/data/repositories/mock_message_moderation_repository.dart';
import 'package:america_hub/features/messaging/data/repositories/mock_messaging_repository.dart';
import 'package:america_hub/features/profile/application/profile_controller.dart';
import 'package:america_hub/features/profile/data/repositories/mock_profile_repository.dart';
import 'package:america_hub/features/verification/application/member_capabilities_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('starts on the two-step TurkSquare login screen', (tester) async {
    final communityRepository = MockCommunityRepository();
    // Home and capabilities have no mock repository: they read straight from
    // an ApiClient. The login screen never triggers either request, and both
    // controllers swallow load failures, so an unreachable client is enough.
    final apiClient = ApiClient(tokenStore: InMemoryTokenStore());
    await tester.pumpWidget(
      AmericaHubApp(
        authController: AuthController(
          repository: MockAuthRepository(),
          sessionStore: InMemorySessionStore(),
          tokenStore: InMemoryTokenStore(),
        ),
        communityController: CommunityFeedController(
          repository: communityRepository,
          commands: communityRepository,
          interactions: communityRepository,
        ),
        storyController: StoryController(repository: communityRepository),
        commentsController: CommunityCommentsController(repository: MockCommunityCommentsRepository()),
        profilePostsController: ProfilePostsController(archive: communityRepository),
        mediaUploadController: MediaUploadController(repository: MockMediaUploadRepository()),
        specialRequestController: CommunitySpecialRequestController(repository: MockCommunitySpecialRequestRepository()),
        eventsController: EventsController(repository: MockEventsRepository()),
        marketplaceController: MarketplaceController(repository: MockMarketplaceRepository()),
        profileController: ProfileController(repository: MockProfileRepository()),
        messagingController: MessagingController(repository: MockMessagingRepository()),
        directMessageRepository: MockDirectMessageRepository(),
        messageModerationRepository: MockMessageModerationRepository(),
        contentModerationRepository: MockContentModerationRepository(),
        communityHomeController: CommunityHomeController(
          CommunityHomeRepository(apiClient),
        ),
        memberCapabilitiesController: MemberCapabilitiesController(
          apiClient,
          apiClient,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    expect(find.text('Hesap oluştur'), findsOneWidget);
    expect(find.text('Devam et'), findsOneWidget);
    expect(find.text('Google ile devam et'), findsOneWidget);
  });
}
