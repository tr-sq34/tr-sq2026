abstract final class ApiEndpoints {
  // ApiConfig.baseUrl already contains `/v1`; keep endpoint paths relative so
  // requests resolve to https://api.turksquare.com/v1/auth/… exactly once.
  static const authLogin = 'auth/login';
  static const authEmailStatus = 'auth/email/status';
  static const authEmailVerificationConfirm = 'auth/email/verification/confirm';
  static const authEmailVerificationResend = 'auth/email/verification/resend';
  static const authPasswordResetRequest = 'auth/password-reset/request';
  static const authPasswordResetVerify = 'auth/password-reset/verify';
  static const authPasswordResetConfirm = 'auth/password-reset/confirm';
  static const authRegister = 'auth/register';
  static const authRefresh = 'auth/refresh';
  static const authLogout = 'auth/logout';
  static const authOnboarding = 'auth/onboarding';
  static const authPasskeyRegistrationOptions =
      'auth/passkeys/registration/options';
  static const authPasskeyRegistrationVerify =
      'auth/passkeys/registration/verify';
  static const authPasskeyAuthenticationOptions =
      'auth/passkeys/authentication/options';
  static const authPasskeyAuthenticationVerify =
      'auth/passkeys/authentication/verify';
  static const communityFeed = '/community/feed';
  static const communityHomeSummary = '/community/home/summary';
  static const communityPosts = '/community/posts';
  static const communityStories = '/community/stories';
  static const communityStoryAudienceContacts =
      '/community/me/story-audience-contacts';
  static const communityMyStoryHighlights = '/community/me/story-highlights';
  static const mediaUploadPresign = '/media/uploads/presign';
  // Served by the messaging gateway, so these resolve against
  // ApiConfig.messagingBaseUrl rather than the identity or community base URL.
  static const messagingConversations = '/messages/conversations';
  static const messagingDirectConversations = '/messages/direct-conversations';
  static String messagingConversationMessages(String conversationId) =>
      '/messages/conversations/$conversationId/messages';
  static const messagingGroups = '/messages/groups';
  static String messagingGroupJoin(String groupId) =>
      '/messages/groups/$groupId/join';
  static String messagingGroupLeave(String groupId) =>
      '/messages/groups/$groupId/leave';
  static String messagingGroupRequests(String groupId) =>
      '/messages/groups/$groupId/requests';
  static String messagingGroupRequest(String groupId, String userId) =>
      '/messages/groups/$groupId/requests/$userId';
  static const messagingReports = '/messages/reports';
  // Blocking is a social-graph edge, so it is owned by the community service
  // and resolves against ApiConfig.communityBaseUrl. Messaging only consumes
  // the event it emits.
  static const communityBlocks = '/community/blocks';
  static String communityBlock(String userId) => '/community/blocks/$userId';
  // Posts, comments and stories are all reported here: the community service
  // owns them, so it is the only place that can copy the reported content into
  // the report before the author can delete it.
  static const communityReports = '/community/reports';
  static const communityMyRestriction = '/community/restrictions/me';
  // The member's identity inside the app: name and locality come from the
  // onboarding projection, bio and avatar from what they typed in Community.
  // Both are served by the community service, which is why they resolve against
  // ApiConfig.communityBaseUrl rather than the identity URL.
  static const communityProfileMe = '/community/profiles/me';
  static String communityProfile(String userId) => '/community/profiles/$userId';
  static String communityProfilePosts(String userId) =>
      '/community/profiles/$userId/posts';
  static String communityPostArchive(String postId) =>
      '/community/posts/$postId/archive';
  // Akış yorumları. Silme ucu paylaşımı değil yorumu adresliyor; sunucu yorumu
  // ya yazanın ya da paylaşım sahibinin kaldırabileceğini oradan çözüyor.
  static String communityPostComments(String postId) =>
      '/community/posts/$postId/comments';
  static String communityPostComment(String commentId) =>
      '/community/comments/$commentId';
  // Beğeni PUT: gövde son durumu söylüyor, artış değil. Aynı isteğin ikincisi
  // sayıyı ikiye katlamasin diye.
  static String communityPostCommentLikes(String commentId) =>
      '/community/comments/$commentId/likes';
  static const communityJourney = '/community/me/journey';
  static const communityBadges = '/community/badges';
  static String communityUserBadges(String userId) =>
      '/community/users/$userId/badges';
  static const communityLeaderboard = '/community/leaderboard';
  // Haber Merkezi ile ana sayfanın manşet şeridi aynı uçtan beslenir; manşet
  // olan haber, listedeki haberin editör tarafından sıralanmış hâlidir.
  static const communityNews = '/community/news';
  static const communityNewsHeadlines = '/community/news/headlines';
  static String communityNewsArticle(String id) => '/community/news/$id';
  static String communityNewsReactions(String id) =>
      '/community/news/$id/reactions';
  static String communityNewsComments(String id) =>
      '/community/news/$id/comments';
  static String communityNewsComment(String commentId) =>
      '/community/news/comments/$commentId';
  static String communityNewsCommentLikes(String commentId) =>
      '/community/news/comments/$commentId/likes';
  // Sponsorlu alanlar: ana sayfanın okuduğu liste, üyenin kendi talepleri ve
  // günlük toplanan gösterim/tıklama sayacı.
  static const communityPromotions = '/community/promotions';
  static const communityPromotionsActive = '/community/promotions/active';
  static const communityMyPromotions = '/community/promotions/me';
  static String communityPromotionEvents(String id) =>
      '/community/promotions/$id/events';
  // Forum: kategoriler, konular ve yanıtlar. Beğeni uçlarının PUT olması
  // bilinçli — aynı isteği iki kez göndermek sayacı iki kez artırmasın.
  static const communityForumCategories = '/community/forum/categories';
  static const communityForumTopics = '/community/forum/topics';
  static const communityForumTrending = '/community/forum/topics/trending';
  static String communityForumTopic(String id) => '/community/forum/topics/$id';
  static String communityForumTopicLike(String id) =>
      '/community/forum/topics/$id/like';
  static String communityForumReplies(String id) =>
      '/community/forum/topics/$id/replies';
  static String communityForumReplyLike(String id) =>
      '/community/forum/replies/$id/like';
  // Yardım çağrısı. Topluluk servisinde duruyor ama `/community` altında
  // değil: bu uçların hiçbiri sosyal bir kayıt değil, üyenin acil durumu.
  static const safetySos = '/safety/sos';
  static const safetySosActive = '/safety/sos/active';
  static String safetySosCancel(String id) => '/safety/sos/$id/cancel';
  static const eventsUpcoming = '/events';
  static String eventRsvp(String id) => '/events/$id/rsvp';
  static const marketplaceListings = '/marketplace/listings';
  static const profile = '/profile/me';
}
