import 'dart:ui';
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/storage/session_store.dart';
import 'core/storage/token_store.dart';
import 'core/network/api_client.dart';
import 'core/network/api_config.dart';
import 'core/cache/cache_store.dart';
import 'features/auth/application/auth_controller.dart';
import 'features/auth/data/repositories/mock_auth_repository.dart';
import 'features/auth/data/repositories/api_auth_repository.dart';
import 'features/auth/data/services/native_passkey_service.dart';
import 'features/auth/domain/repositories/auth_repository.dart';
import 'features/community/application/community_feed_controller.dart';
import 'features/community/application/story_controller.dart';
import 'features/community/application/community_comments_controller.dart';
import 'features/community/application/media_upload_controller.dart';
import 'features/community/application/community_special_request_controller.dart';
import 'features/community/data/repositories/mock_community_repository.dart';
import 'features/community/data/repositories/api_community_repository.dart';
import 'features/community/domain/repositories/community_repository.dart';
import 'features/community/data/repositories/mock_community_comments_repository.dart';
import 'features/community/data/repositories/mock_media_upload_repository.dart';
import 'features/community/data/repositories/api_media_upload_repository.dart';
import 'features/community/domain/repositories/media_upload_repository.dart';
import 'features/community/data/repositories/mock_community_special_request_repository.dart';
import 'features/community/data/repositories/cached_community_repository.dart';
import 'features/events/application/events_controller.dart';
import 'features/events/data/repositories/mock_events_repository.dart';
import 'features/events/data/repositories/cached_events_repository.dart';
import 'features/marketplace/application/marketplace_controller.dart';
import 'features/marketplace/data/repositories/mock_marketplace_repository.dart';
import 'features/marketplace/data/repositories/api_marketplace_repository.dart';
import 'features/marketplace/data/repositories/cached_marketplace_repository.dart';
import 'features/marketplace/data/repositories/mock_marketplace_listing_analyzer.dart';
import 'features/profile/application/profile_controller.dart';
import 'features/profile/data/repositories/api_profile_repository.dart';
import 'features/profile/data/repositories/mock_profile_repository.dart';
import 'features/profile/domain/repositories/profile_repository.dart';
import 'features/journey/application/journey_controller.dart';
import 'features/journey/data/repositories/api_journey_repository.dart';
import 'features/journey/data/repositories/mock_journey_repository.dart';
import 'features/journey/domain/repositories/journey_repository.dart';
import 'features/messaging/application/messaging_controller.dart';
import 'features/community/data/repositories/api_content_moderation_repository.dart';
import 'features/community/data/repositories/mock_content_moderation_repository.dart';
import 'features/community/domain/repositories/content_moderation_repository.dart';
import 'features/messaging/data/repositories/api_message_moderation_repository.dart';
import 'features/messaging/data/repositories/api_messaging_repository.dart';
import 'features/messaging/data/repositories/mock_direct_message_repository.dart';
import 'features/messaging/data/repositories/mock_message_moderation_repository.dart';
import 'features/messaging/data/repositories/mock_messaging_repository.dart';
import 'features/messaging/domain/repositories/direct_message_repository.dart';
import 'features/messaging/domain/repositories/message_moderation_repository.dart';
import 'features/home/application/community_home_controller.dart';
import 'features/home/data/community_home_repository.dart';
import 'features/notifications/application/notifications_controller.dart';
import 'features/notifications/data/repositories/empty_notification_repository.dart';
import 'features/verification/application/member_capabilities_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Handle uncaught errors to prevent immediate connection drop without logs
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    debugPrint('Uncaught error: $error\n$stackTrace');
    return true;
  };

  final sessionStore = await SharedPreferencesSessionStore.create();
  final tokenStore = SecureTokenStore();
  final cacheStore = await SharedPreferencesCacheStore.create();

  const useMockServices = bool.fromEnvironment(
    'USE_MOCK_SERVICES',
    defaultValue: false, // Default to true for dev safety
  );

  late final AuthController authController;
  final apiClient = ApiClient(
    tokenStore: tokenStore,
    onSessionExpired: () => authController.expireSession(),
  );
  final communityApiClient = ApiClient(
    tokenStore: tokenStore,
    baseUrl: ApiConfig.communityBaseUrl,
    onSessionExpired: () => authController.expireSession(),
  );
  final verificationApiClient = ApiClient(
    tokenStore: tokenStore,
    baseUrl: ApiConfig.verificationBaseUrl,
    onSessionExpired: () => authController.expireSession(),
  );
  final messagingApiClient = ApiClient(
    tokenStore: tokenStore,
    baseUrl: ApiConfig.messagingBaseUrl,
    onSessionExpired: () => authController.expireSession(),
  );

  // One mock auth object for the whole app: it is the only thing that knows who
  // signed in and what they answered during setup, and the mock profile reads
  // that instead of inventing a member of its own.
  final mockAuthRepository = MockAuthRepository(cacheStore: cacheStore);
  final AuthRepository authRepository = useMockServices
      ? mockAuthRepository
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

  final mockCommunityRemote = MockCommunityRepository();
  final CommunityRepository communityRemote = useMockServices
      ? mockCommunityRemote
      : ApiCommunityRepository(client: communityApiClient);
  final CommunityPostCommands communityCommands = useMockServices
      ? mockCommunityRemote
      : ApiCommunityRepository(client: communityApiClient);
  final PostInteractionRepository communityInteractions = useMockServices
      ? mockCommunityRemote
      : ApiCommunityRepository(client: communityApiClient);
  final StoryRepository storyRepository = useMockServices
      ? mockCommunityRemote
      : ApiCommunityRepository(client: communityApiClient);

  final communityRepository = CachedCommunityRepository(
    remote: communityRemote,
    cacheStore: cacheStore,
  );

  final communityController = CommunityFeedController(
    repository: communityRepository,
    commands: communityCommands,
    interactions: communityInteractions,
    onMutationCommitted: () => communityRepository.invalidateFirstPage(),
  );
  final storyController = StoryController(repository: storyRepository);

  final communityHomeController = CommunityHomeController(
    CommunityHomeRepository(communityApiClient),
  );

  final memberCapabilitiesController = MemberCapabilitiesController(
    communityApiClient,
    verificationApiClient,
  );

  final commentsController = CommunityCommentsController(
    repository: MockCommunityCommentsRepository(),
  );

  // Shared with the profile repository, which needs it to turn an upload id
  // back into the file the member picked.
  final mockMediaUploadRepository = MockMediaUploadRepository();
  final MediaUploadRepository mediaUploadRepository = useMockServices
      ? mockMediaUploadRepository
      : ApiMediaUploadRepository(client: communityApiClient);
  final mediaUploadController = MediaUploadController(
    repository: mediaUploadRepository,
  );

  final specialRequestController = CommunitySpecialRequestController(
    repository: MockCommunitySpecialRequestRepository(),
  );

  final eventsController = EventsController(
    repository: CachedEventsRepository(
      remote: MockEventsRepository(),
      cacheStore: cacheStore,
    ),
  );

  final marketplaceController = MarketplaceController(
    repository: CachedMarketplaceRepository(
      remote: useMockServices
          ? MockMarketplaceRepository()
          : ApiMarketplaceRepository(client: communityApiClient),
      cacheStore: cacheStore,
    ),
    analyzer: MockMarketplaceListingAnalyzer(),
    draftStore: cacheStore,
  );

  final ProfileRepository profileRepository = useMockServices
      ? MockProfileRepository(
          auth: mockAuthRepository,
          cacheStore: cacheStore,
          media: mockMediaUploadRepository,
        )
      : ApiProfileRepository(client: communityApiClient);
  final profileController = ProfileController(repository: profileRepository);

  final JourneyRepository journeyRepository = useMockServices
      ? const MockJourneyRepository()
      : ApiJourneyRepository(client: communityApiClient);
  final journeyController = JourneyController(repository: journeyRepository);

  // One object serves both messaging roles against the gateway, so the inbox
  // list and an open thread always agree about what a conversation is.
  final apiMessagingRepository = ApiMessagingRepository(
    client: messagingApiClient,
  );
  final messagingController = MessagingController(
    repository: useMockServices
        ? MockMessagingRepository()
        : apiMessagingRepository,
  );
  final DirectMessageRepository directMessageRepository = useMockServices
      ? MockDirectMessageRepository(viewerId: authController.user?.id ?? 'me')
      : apiMessagingRepository;
  final MessageModerationRepository messageModerationRepository =
      useMockServices
      ? MockMessageModerationRepository()
      : ApiMessageModerationRepository(
          messagingClient: messagingApiClient,
          communityClient: communityApiClient,
        );
  final ContentModerationRepository contentModerationRepository =
      useMockServices
      ? MockContentModerationRepository()
      : ApiContentModerationRepository(client: communityApiClient);

  // Deliberately empty on both sides of the mock flag: no service publishes
  // member notifications yet, so the bell stays at zero until one does.
  final notificationsController = NotificationsController(
    repository: const EmptyNotificationRepository(),
  );

  runApp(
    AmericaHubApp(
      authController: authController,
      communityController: communityController,
      storyController: storyController,
      commentsController: commentsController,
      mediaUploadController: mediaUploadController,
      postCommands: communityCommands,
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
    ),
  );
}
