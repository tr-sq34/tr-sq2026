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
import 'features/forum/application/forum_controller.dart';
import 'features/forum/data/repositories/api_forum_repository.dart';
import 'features/forum/data/repositories/mock_forum_repository.dart';
import 'features/forum/domain/repositories/forum_repository.dart';
import 'features/news/application/news_controller.dart';
import 'features/news/data/repositories/api_news_comments_repository.dart';
import 'features/news/data/repositories/api_news_repository.dart';
import 'features/news/data/repositories/mock_news_comments_repository.dart';
import 'features/news/data/repositories/mock_news_repository.dart';
import 'features/news/domain/repositories/news_repository.dart';
import 'features/notifications/application/notifications_controller.dart';
import 'features/promotions/application/promotions_controller.dart';
import 'features/promotions/data/repositories/api_promotion_repository.dart';
import 'features/promotions/data/repositories/mock_promotion_repository.dart';
import 'features/promotions/domain/repositories/promotion_repository.dart';
import 'features/notifications/data/repositories/empty_notification_repository.dart';
import 'features/safety/application/sos_controller.dart';
import 'features/safety/data/sos_repository.dart';
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
  // Sahte servislerle çalışırken sunucuda bir oturum yok: jeton da sahte, o
  // yüzden hâlâ API'ye giden birkaç okuma (ana sayfa özeti, üyelik yetkileri)
  // 401 dönüyor ve üyeyi sessizce oturumdan atıyordu — giriş yapılmış olmasına
  // rağmen kabuk "Üye" diyor, düzenleyici paylaşımı "Sen" diye imzalıyordu.
  Future<void> handleSessionExpired() async {
    if (useMockServices) return;
    await authController.expireSession();
  }

  final apiClient = ApiClient(
    tokenStore: tokenStore,
    onSessionExpired: handleSessionExpired,
  );
  final communityApiClient = ApiClient(
    tokenStore: tokenStore,
    baseUrl: ApiConfig.communityBaseUrl,
    onSessionExpired: handleSessionExpired,
  );
  final verificationApiClient = ApiClient(
    tokenStore: tokenStore,
    baseUrl: ApiConfig.verificationBaseUrl,
    onSessionExpired: handleSessionExpired,
  );
  final messagingApiClient = ApiClient(
    tokenStore: tokenStore,
    baseUrl: ApiConfig.messagingBaseUrl,
    onSessionExpired: handleSessionExpired,
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

  // Sahte depo da paylaşımı imzalayan kişiyi bilmek zorunda: sabit bir isim,
  // üyenin kendi paylaşımını başkasının adıyla görmesi demekti.
  final mockCommunityRemote = MockCommunityRepository(
    viewer: () => authController.user,
    viewerRegion: () async => (await mockAuthRepository.getOnboarding()).regionCode,
  );
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
  final PollRepository communityPolls = useMockServices
      ? mockCommunityRemote
      : ApiCommunityRepository(client: communityApiClient);

  final communityRepository = CachedCommunityRepository(
    remote: communityRemote,
    cacheStore: cacheStore,
  );

  // Sekme sunucuda: "Yakınındakiler" ve "Takip ettiklerin" ayrı bir sorgu, o
  // yüzden akış denetleyicisi önbellekli depoya ek olarak uzak depoyu da alıyor.
  final FeedRepository communityFeed = useMockServices
      ? mockCommunityRemote
      : ApiCommunityRepository(client: communityApiClient);

  final communityController = CommunityFeedController(
    repository: communityRepository,
    feed: communityFeed,
    commands: communityCommands,
    interactions: communityInteractions,
    polls: communityPolls,
    onMutationCommitted: () => communityRepository.invalidateFirstPage(),
  );
  final storyController = StoryController(repository: storyRepository);

  final communityHomeController = CommunityHomeController(
    useMockServices
        ? MockCommunityHomeRepository(
            feed: mockCommunityRemote,
            stories: mockCommunityRemote,
            onboarding: mockAuthRepository.getOnboarding,
            viewerId: () => mockCommunityRemote.viewerId,
          )
        : ApiCommunityHomeRepository(communityApiClient),
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
          // Izgara ayrı bir demo listesi değil, akışın kendisi: paylaşılan
          // gönderi aynı anda profilde de görünüyor.
          posts: mockCommunityRemote,
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

  // The Haber Merkezi and the home screen's "Amerika'dan Manşetler" strip read
  // the same repository, so a headline can never drift from the article behind
  // it. News comments deliberately reuse the feed's comment controller and
  // sheet: one editor, two surfaces.
  final NewsRepository newsRepository = useMockServices
      ? MockNewsRepository()
      : ApiNewsRepository(client: communityApiClient);
  final newsController = NewsController(repository: newsRepository);
  final newsCommentsController = CommunityCommentsController(
    repository: useMockServices
        ? MockNewsCommentsRepository(viewer: () => authController.user)
        : ApiNewsCommentsRepository(client: communityApiClient),
  );

  // Forum menüden de açılıyor, ana sayfadaki trend şeridinden de; ikisi tek
  // denetleyiciyi paylaşıyor ki şeritte görünen sayı ile konuda yazan sayı
  // ayrışmasın.
  final ForumRepository forumRepository = useMockServices
      ? MockForumRepository(viewer: () => authController.user)
      : ApiForumRepository(client: communityApiClient);
  final forumController = ForumController(repository: forumRepository);

  // The sponsored story slot, the in-app banner and the "Sana Özel Öne Çıkanlar"
  // cards are one record with a placement on it, so one repository serves all
  // three. Nothing here charges anybody: a request is approved on its merits.
  final PromotionRepository promotionRepository = useMockServices
      ? MockPromotionRepository()
      : ApiPromotionRepository(client: communityApiClient);
  final promotionsController = PromotionsController(
    repository: promotionRepository,
  );

  // Yardım çağrısının sahtesi yok ve olmayacak: gönderilmiş gibi görünüp
  // kimseye ulaşmayan bir SOS, hiç olmayan bir SOS'tan daha kötüdür. Sahte
  // servis kipinde de gerçek uca gider, ulaşamazsa ekran bunu söyler.
  final sosController = SosController(
    repository: ApiSosRepository(client: communityApiClient),
  );

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
      newsController: newsController,
      newsCommentsController: newsCommentsController,
      promotionsController: promotionsController,
      forumController: forumController,
      sosController: sosController,
    ),
  );
}
