abstract final class ApiEndpoints {
  // ApiConfig.baseUrl already contains `/v1`; keep endpoint paths relative so
  // requests resolve to https://api.turksquare.com/v1/auth/… exactly once.
  static const authLogin = 'auth/login';
  static const authEmailStatus = 'auth/email/status';
  static const authEmailVerificationConfirm = 'auth/email/verification/confirm';
  static const authEmailVerificationResend = 'auth/email/verification/resend';
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
  static const eventsUpcoming = '/events';
  static const marketplaceListings = '/marketplace/listings';
  static const profile = '/profile/me';
}
